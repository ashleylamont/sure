require "digest"

class GoalFundingPlan < ApplicationRecord
  CONFIGURATION_FIELDS = %w[name backing_account_id source_account_id sample_entry_id currency source_name source_notes minimum_salary maximum_salary effective_on].freeze

  belongs_to :family
  belongs_to :user, optional: true
  belongs_to :backing_account, class_name: "Account", optional: true
  belongs_to :source_account, class_name: "Account", optional: true
  belongs_to :sample_entry, class_name: "Entry", optional: true
  has_many :rules, class_name: "GoalFundingRule", dependent: :destroy, autosave: true, inverse_of: :goal_funding_plan
  has_many :runs, class_name: "GoalFundingRun", dependent: :delete_all

  validates :name, :source_name, :currency, :effective_on, presence: true
  validates :name, length: { maximum: 255 }
  validates :source_name, length: { maximum: 1000 }
  validates :minimum_salary, numericality: { greater_than: 0 }
  validates :maximum_salary, numericality: { greater_than_or_equal_to: :minimum_salary }
  validate :valid_configuration

  scope :enabled, -> { where(enabled: true) }

  def self.for_user(user)
    where(family_id: user.family_id, user_id: user.id)
  end

  def configure!(actor:, attributes:, rules:, expected_revision: nil)
    self.class.transaction(requires_new: true) do
      lock! if persisted?
      authorize_owner!(actor)
      if persisted? && expected_revision.to_s != revision.to_s
        raise Goal::AllocationError.new(:stale_state, status: :conflict)
      end
      prior = configuration_fingerprint if persisted?
      values = attributes.to_h.stringify_keys.slice(*CONFIGURATION_FIELDS)
      values["effective_on"] = Date.iso8601(values["effective_on"]) if values["effective_on"].present?
      %w[minimum_salary maximum_salary].each do |field|
        values[field] = Goal::FundingAccess.decimal(values[field], positive: true) if values.key?(field)
      end
      assign_attributes(values)
      if sample_entry_id.present?
        sample = actor.accessible_accounts.joins(:entries).find_by!(entries: { id: sample_entry_id }).entries.find(sample_entry_id)
        self.source_account_id = sample.account_id
        self.source_name = sample.name if source_name.blank?
      end
      self.currency = backing_account&.currency
      self.effective_on ||= family.local_date.next_day
      if rules
        self.rules.each(&:mark_for_destruction)
        Array(rules).each do |raw|
          item = raw.to_h.stringify_keys
          amount = Goal::FundingAccess.decimal(item["amount"], positive: true)
          goal = Goal::FundingAccess.goals(actor, write: true).find(item["goal_id"])
          self.rules.build(goal: goal, amount: amount, stop_at_target: ActiveModel::Type::Boolean.new.cast(item["stop_at_target"]) || false)
        end
      end
      changed = new_record? || prior != configuration_fingerprint
      self.revision += 1 if persisted? && changed
      self.enabled = false if changed
      save!
      runs.where(status: %w[pending awaiting_funds]).update_all(status: "needs_review", reason_code: "configuration_changed", updated_at: Time.current) if changed
    end
    self
  end

  def authorize_owner!(actor = user)
    unless actor&.active? && !actor.guest? && actor.id == user_id && actor.family_id == family_id
      raise Goal::AllocationError.new(:forbidden, status: :forbidden)
    end
  end

  def validate_access!
    authorize_owner!
    Goal::FundingAccess.accounts(user, write: true).where(accountable_type: "Depository").find(backing_account_id)
    user.accessible_accounts.visible.where(accountable_type: "Depository").find(source_account_id)
    current_rules = rules.reject(&:marked_for_destruction?)
    permitted = Goal::FundingAccess.goals(user, write: true).where(id: current_rules.map(&:goal_id)).pluck(:id)
    raise ActiveRecord::RecordNotFound unless current_rules.all? { |rule| rule.goal_id.nil? || permitted.include?(rule.goal_id) }
    unless backing_account.currency == currency && source_account.currency == currency
      raise Goal::AllocationError.new(:currency_mismatch)
    end
  end

  def preview(entry: sample_entry, run: nil)
    validate_access!
    snapshot = Goal::CashReservation.new(backing_account.reload, user: user)
    payload = rules.reload.order(:goal_id).map(&:snapshot)
    total = payload.sum(0.to_d) { |rule| BigDecimal(rule.fetch("amount")) }
    reason = payload.filter_map { |rule| rule["review_reason"] }.first || snapshot.review_reason
    reason ||= "insufficient_cash" if total > snapshot.unallocated
    if run && !eligible_source?(entry, check_boundary: false)
      reason = "source_changed"
    elsif run && !source_reconciled?
      reason = "source_not_reconciled"
    end
    signature = preview_signature(snapshot, payload, entry, run)
    {
      plan_id: id, revision: revision, rules: payload, total: total.to_s("F"),
      account: snapshot.as_json, reason_code: reason, allowed: reason.nil?,
      historical: entry && !eligible_source?(entry),
      source: entry && { id: entry.id, name: entry.name, date: entry.date, amount: entry.amount.abs.to_s("F"), account_id: entry.account_id },
      matches: matching_transactions.limit(20).map { |transaction| { id: transaction.entry.id, name: transaction.entry.name, date: transaction.entry.date, amount: transaction.entry.amount.abs.to_s("F") } },
      preview_token: verifier.generate(signature, expires_in: 15.minutes, purpose: "funding")
    }
  end

  def enable!(actor:, preview_token:, confirm_salary_source: false)
    with_lock do
      authorize_owner!(actor)
      raise Goal::AllocationError.new(:preview_disabled, status: :forbidden) unless actor.preview_features_enabled?
      return self if enabled?
      raise Goal::AllocationError.new(:preview_required) unless ActiveModel::Type::Boolean.new.cast(confirm_salary_source)
      Goal::AllocationAdjustment.with_account_locks([ backing_account_id ]) do
        data = preview
        verify_preview!(preview_token, entry: sample_entry)
        rule_error = data[:rules].filter_map { |rule| rule["review_reason"] }.first
        raise Goal::AllocationError.new(rule_error) if rule_error
        if data[:account][:review_reason] == "whole_account_conversion_required"
          raise Goal::AllocationError.new(:whole_account_conversion_required)
        end
        update!(enabled: true, enabled_at: Time.current)
      end
    end
    self
  end

  def disable!(actor:)
    with_lock do
      authorize_owner!(actor)
      update_columns(enabled: false, updated_at: Time.current)
      runs.where(status: %w[pending awaiting_funds]).update_all(status: "needs_review", reason_code: "plan_disabled", updated_at: Time.current)
    end
    self
  end

  def verify_preview!(token, entry: sample_entry, run: nil)
    snapshot = Goal::CashReservation.new(backing_account.reload, user: user)
    payload = rules.reload.order(:goal_id).map(&:snapshot)
    unless verifier.verified(token, purpose: "funding") == preview_signature(snapshot, payload, entry, run)
      raise Goal::AllocationError.new(:stale_preview, status: :conflict)
    end
    payload
  end

  def automatic_start_on
    [ effective_on, enabled_at && family.local_date(enabled_at).next_day ].compact.max
  end

  def eligible_source?(entry, check_boundary: true)
    return false unless entry&.transaction? && entry.account_id == source_account_id && entry.currency == currency
    return false if source_account.syncs.incomplete.exists?
    return false unless entry.amount.negative? && !entry.excluded? && entry.parent_entry_id.nil? && entry.child_entries.empty?
    return false unless entry.entryable.standard? && !entry.entryable.transfer? && !entry.entryable.pending?
    return false if entry.date > family.local_date
    return false if check_boundary && (enabled_at.nil? || entry.date < automatic_start_on)
    return false unless entry.amount.abs.between?(minimum_salary, maximum_salary)
    return false if source_notes.present? && !entry.notes.to_s.include?(source_notes)

    name_filter.apply(name_filter.prepare(Transaction.where(id: entry.entryable_id)), "=", source_name).exists?
  end

  def matching_transactions
    scope = Transaction.excluding_pending.where(kind: "standard", transfer_id: nil)
      .joins(:entry).where(entries: { account_id: source_account_id, currency: currency, excluded: false, parent_entry_id: nil })
      .where.not(entries: { id: Entry.where.not(parent_entry_id: nil).select(:parent_entry_id) })
      .where("entries.amount BETWEEN ? AND ?", -maximum_salary, -minimum_salary)
    scope = name_filter.apply(scope, "=", source_name)
    scope = scope.where("POSITION(? IN COALESCE(entries.notes, '')) > 0", source_notes) if source_notes.present?
    scope.includes(:entry).order("entries.date DESC", "entries.id DESC")
  end

  def recover!
    return unless enabled?
    validate_access!
    matching_transactions.where(entries: { date: automatic_start_on..family.local_date })
      .where.not(entries: { id: runs.select(:source_entry_id) })
      .reorder("entries.date ASC", "entries.created_at ASC", "entries.id ASC").limit(100).each do |transaction|
      process_source!(transaction.entry)
    end
    runs.where(status: %w[pending awaiting_funds]).order(:source_date, :created_at).limit(100).each(&:apply!)
  rescue Goal::AllocationError, ActiveRecord::RecordNotFound => error
    runs.where(status: %w[pending awaiting_funds]).update_all(status: "needs_review", reason_code: "permission_changed", updated_at: Time.current)
    DebugLogEntry.capture(category: "goal_funding", level: "warn", message: "Funding plan needs an access/configuration review",
                          source: self.class.name, family: family, account: backing_account,
                          metadata: { plan_id: id, error_class: error.class.name })
  end

  def process_source!(entry)
    run = nil
    with_lock do
      return unless enabled? && source_reconciled? && eligible_source?(entry)
      run = runs.find_by(source_entry_id: entry.id)
      unless run
        newer = runs.where("source_date > ?", entry.date).exists?
        unless newer
          runs.where(status: %w[pending awaiting_funds]).update_all(status: "needs_review", reason_code: "newer_payday", updated_at: Time.current)
        end
        run = runs.create!(source_entry_id: entry.id, source_fingerprint: GoalFundingRun.fingerprint(entry),
                           source_date: entry.date, plan_revision: revision, rules_snapshot: rules.order(:goal_id).map(&:snapshot),
                           status: newer ? "needs_review" : "pending", reason_code: newer ? "newer_payday" : nil)
      end
    end
    run.apply!
    run
  end

  def source_reconciled?
    account = source_account&.reload
    account && account.goal_cash_reconciled_at && !account.syncs.incomplete.exists?
  end

  private
    def name_filter
      Rule::ConditionFilter::TransactionName.new(nil)
    end

    def configuration_fingerprint
      [ attributes.slice(*CONFIGURATION_FIELDS), rules.reject(&:marked_for_destruction?).map { |rule| [ rule.goal_id, rule.amount&.to_s("F"), rule.stop_at_target? ] }.sort_by(&:first) ].to_json
    end

    def valid_configuration
      current_rules = rules.reject(&:marked_for_destruction?)
      errors.add(:base, :funding_rules_required) if current_rules.empty? || current_rules.size > 30
      errors.add(:base, :duplicate_funding_goal) if current_rules.map(&:goal_id).uniq.size != current_rules.size
      return unless user && backing_account && source_account && sample_entry && minimum_salary && maximum_salary

      validate_access!
      unless sample_entry.account_id == source_account_id && eligible_source?(sample_entry, check_boundary: false)
        errors.add(:sample_entry, :invalid)
      end
    rescue Goal::AllocationError, ActiveRecord::RecordNotFound
      errors.add(:base, :funding_access_invalid)
    ensure
      errors.add(:backing_account, :blank) unless backing_account
      errors.add(:source_account, :blank) unless source_account
      errors.add(:sample_entry, :blank) unless sample_entry
    end

    def preview_signature(snapshot, payload, entry, run)
      { "user_id" => user_id, "plan_id" => id, "revision" => revision,
        "account_version" => snapshot.account.goal_allocation_version,
        "rules" => payload, "source" => entry && GoalFundingRun.fingerprint(entry), "run_id" => run&.id }
    end

    def verifier
      Rails.application.message_verifier("goal-funding-preview")
    end
end
