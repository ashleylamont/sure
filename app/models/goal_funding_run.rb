require "digest"

class GoalFundingRun < ApplicationRecord
  belongs_to :goal_funding_plan
  belongs_to :source_entry, class_name: "Entry", optional: true

  STATUSES = %w[pending applied awaiting_funds needs_review skipped failed reversed].freeze
  validates :status, inclusion: { in: STATUSES }

  def self.fingerprint(entry)
    return Digest::SHA256.hexdigest(entry.attributes.to_json) unless entry.transaction?
    transaction = entry.entryable
    Digest::SHA256.hexdigest([
      entry.id, entry.account_id, entry.name, entry.notes, entry.date, entry.amount.to_s("F"), entry.currency,
      entry.excluded, entry.parent_entry_id,
      transaction.kind, transaction.transfer_id, transaction.merchant_id, transaction.category_id, transaction.pending?
    ].to_json)
  end

  def apply!
    self.class.transaction(requires_new: true) do
      plan = goal_funding_plan
      plan.lock!
      lock!
      return self if applied_at || !%w[pending awaiting_funds].include?(status)
      return review!(:plan_disabled) unless plan.enabled?
      return review!(:configuration_changed) unless plan_revision == plan.revision

      Goal::AllocationAdjustment.with_account_locks([ plan.backing_account_id, plan.source_account_id ].compact.uniq) do
        plan.validate_access!
        unless plan.source_reconciled?
          update!(status: "awaiting_funds", reason_code: "source_not_reconciled")
          return self
        end
        source = Entry.lock.find_by(id: source_entry_id)
        unless plan.eligible_source?(source, check_boundary: false) && self.class.fingerprint(source) == source_fingerprint
          return review!(:source_changed)
        end

        current = plan.rules.reload.order(:goal_id).map(&:snapshot)
        rule_error = current.filter_map { |rule| rule["review_reason"] }.first
        return review!(rule_error) if rule_error
        unless comparable_rules(current) == comparable_rules(rules_snapshot)
          return review!(:configuration_changed)
        end

        account = plan.backing_account.reload
        snapshot = Goal::CashReservation.new(account, user: plan.user)
        return review!(snapshot.review_reason) if snapshot.review_reason
        total = rules_snapshot.sum(0.to_d) { |rule| BigDecimal(rule.fetch("amount")) }
        if snapshot.shortage.positive? || total > snapshot.unallocated
          update!(status: "awaiting_funds", reason_code: "insufficient_cash")
          return self
        end

        operations = rules_snapshot.filter_map do |rule|
          next unless BigDecimal(rule.fetch("amount")).positive?
          { goal_id: rule.fetch("goal_id"), account_id: account.id, mode: "add", amount: rule.fetch("amount") }
        end
        if operations.empty?
          plan.family.goal_allocations.create!(
            user: plan.user, goal_funding_run_id: id, idempotency_key: "funding:#{id}",
            payload_fingerprint: Digest::SHA256.hexdigest(rules_snapshot.to_json), kind: "funding",
            reason: I18n.t("goal_funding.audit.payday"), result: { no_op: true, changes: [] }
          )
        else
          Goal::AllocationAdjustment.new(
            user: plan.user, adjustments: operations, versions: { account.id => account.goal_allocation_version },
            idempotency_key: "funding:#{id}", reason: I18n.t("goal_funding.audit.payday"), funding_run: self, kind: "funding"
          ).apply!
        end
        update!(status: "applied", reason_code: nil, applied_at: Time.current)
      end
    end
    self
  rescue Goal::AllocationError, ActiveRecord::RecordNotFound => error
    review!(error.is_a?(Goal::AllocationError) ? error.code : :permission_changed)
  rescue StandardError => error
    self.class.where(id: id, applied_at: nil).update_all(status: "failed", reason_code: "allocation_failed", updated_at: Time.current)
    DebugLogEntry.capture(category: "goal_funding", level: "error", message: "Payday reservation changes rolled back",
                          source: self.class.name, family: goal_funding_plan.family, account: goal_funding_plan.backing_account,
                          metadata: { run_id: id, error_class: error.class.name })
    reload
  end

  def retry_with_preview!(actor:, preview_token:)
    plan = goal_funding_plan
    self.class.transaction(requires_new: true) do
      plan.lock!
      lock!
      plan.authorize_owner!(actor)
      return self if applied_at
      raise Goal::AllocationError.new(:run_not_retryable) if %w[skipped reversed].include?(status)
      raise Goal::AllocationError.new(:plan_disabled) unless plan.enabled?
      Goal::AllocationAdjustment.with_account_locks([ plan.backing_account_id, plan.source_account_id ].compact.uniq) do
        plan.validate_access!
        entry = Entry.lock.find_by(id: source_entry_id)
        raise Goal::AllocationError.new(:source_changed) unless plan.eligible_source?(entry, check_boundary: false)
        payload = plan.verify_preview!(preview_token, entry: entry, run: self)
        update!(status: "pending", reason_code: nil, plan_revision: plan.revision, rules_snapshot: payload,
                source_fingerprint: self.class.fingerprint(entry),
                review_history: review_history + [ { revision: plan_revision, rules: rules_snapshot,
                                                    actor_id: actor.id, reviewed_at: Time.current.iso8601 } ])
      end
    end
    apply!
  end

  def skip!(actor:)
    with_lock do
      goal_funding_plan.authorize_owner!(actor)
      raise Goal::AllocationError.new(:run_already_applied) if applied_at
      update!(status: "skipped", reason_code: "user_skipped")
    end
    self
  end

  def reversal_preview(actor:)
    goal_funding_plan.authorize_owner!(actor)
    raise Goal::AllocationError.new(:run_not_reversible) unless applied_at && !reversed_at
    reversal_adjustment(actor).preview
  end

  def reverse!(actor:, preview_token:)
    plan = goal_funding_plan
    self.class.transaction(requires_new: true) do
      plan.lock!
      lock!
      plan.authorize_owner!(actor)
      return self if reversed_at
      raise Goal::AllocationError.new(:run_not_reversible) unless applied_at
      adjustment = reversal_adjustment(actor, token: preview_token)
      # Every reversal must be reviewed, including a fixed-only reservation.
      unless preview_token.present?
        raise Goal::AllocationError.new(:preview_required)
      end
      adjustment.apply!
      update!(status: "reversed", reversed_at: Time.current, reason_code: "user_reversed")
    end
    self
  rescue Goal::AllocationError => error
    review!(error.code) if applied_at && !reversed_at
    raise
  end

  def review!(reason)
    update!(status: "needs_review", reason_code: reason.to_s) unless reversed_at
    self
  end

  def check_source!
    return unless applied_at && !reversed_at
    entry = Entry.find_by(id: source_entry_id)
    review!(:source_changed) unless entry && self.class.fingerprint(entry) == source_fingerprint
  end

  private
    def comparable_rules(payload)
      payload.map { |rule| rule.slice("goal_id", "amount", "configured_amount", "stop_at_target", "review_reason") }
    end

    def reversal_adjustment(actor, token: nil)
      batch = GoalAllocation.find_by!(goal_funding_run_id: id, kind: "funding")
      changes = batch.allocation_changes.where("delta > 0").to_a
      raise Goal::AllocationError.new(:run_not_reversible) if changes.empty?
      account_ids = changes.map(&:account_id).uniq
      versions = Goal::FundingAccess.accounts(actor, write: true).where(id: account_ids).pluck(:id, :goal_allocation_version).to_h
      Goal::AllocationAdjustment.new(
        user: actor, adjustments: changes.map { |change| { goal_id: change.goal_id, account_id: change.account_id, mode: "release", amount: change.delta.to_s("F") } },
        versions: versions, idempotency_key: "reverse:#{id}", reason: I18n.t("goal_funding.audit.reversal"),
        preview_token: token, funding_run: self, kind: "reversal"
      )
    end
end
