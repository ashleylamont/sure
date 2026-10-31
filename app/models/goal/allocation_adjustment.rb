require "digest"

class Goal::AllocationAdjustment
  MODES = %w[set add release].freeze

  def initialize(user:, adjustments:, versions: {}, idempotency_key:, reason:, floors: {},
                 preview_token: nil, confirm_conversion: false, funding_run: nil, kind: "manual")
    @user, @key, @reason = user, idempotency_key.to_s, reason.to_s.strip
    unless adjustments.is_a?(Array) && adjustments.all? { |item| item.is_a?(Hash) } && versions.is_a?(Hash) && floors.is_a?(Hash)
      raise Goal::AllocationError.new(:invalid_adjustment)
    end
    @versions = versions.to_h.stringify_keys.transform_values(&:to_s)
    @floors = floors.to_h.transform_keys(&:to_s).transform_values { |value| Goal::FundingAccess.decimal(value) }
    @token, @confirm_conversion, @funding_run, @kind = preview_token, ActiveModel::Type::Boolean.new.cast(confirm_conversion), funding_run, kind
    @operations = Array(adjustments).map do |raw|
      item = raw.to_h.stringify_keys
      mode = item.fetch("mode", "set")
      raise Goal::AllocationError.new(:invalid_adjustment) unless MODES.include?(mode)
      { "account_id" => item["account_id"].to_s, "goal_id" => item["goal_id"].to_s,
        "mode" => mode, "amount" => Goal::FundingAccess.decimal(item["amount"]).to_s("F") }
    end.sort_by { |item| [ item["account_id"], item["goal_id"] ] }
    raise Goal::AllocationError.new(:invalid_adjustment) if @operations.size > 30 || (@operations.empty? && @floors.empty?)
    raise Goal::AllocationError.new(:reason_required) if @reason.blank? || @reason.length > 1000
    raise Goal::AllocationError.new(:idempotency_required) if @key.blank? || @key.length > 200
    pairs = @operations.map { |item| item.values_at("account_id", "goal_id") }
    raise Goal::AllocationError.new(:duplicate_allocation) unless pairs.uniq.size == pairs.size
  end

  def preview
    load_records!
    @versions = @accounts.to_h { |account| [ account.id, account.goal_allocation_version.to_s ] } if @versions.empty?
    proposal = project
    proposal.merge(preview_token: verifier.generate(
      { "fingerprint" => fingerprint, "user_id" => @user.id }, expires_in: 15.minutes, purpose: "allocation"
    ))
  end

  def apply!
    load_records!
    prior = find_prior
    return replay(prior) if prior

    result = nil
    self.class.with_account_locks(@accounts.map(&:id)) do
      load_records!(lock: true)
      prior = find_prior
      if prior
        result = replay(prior)
        next
      end

      check_versions!
      proposal = project
      raise Goal::AllocationError.new(proposal[:reason_code], details: proposal) unless proposal[:allowed]
      if @token.present? && verifier.verified(@token, purpose: "allocation") != { "fingerprint" => fingerprint, "user_id" => @user.id }
        raise Goal::AllocationError.new(:stale_preview, status: :conflict)
      end
      if proposal[:requires_conversion]
        verified = verifier.verified(@token, purpose: "allocation")
        unless @confirm_conversion && verified == { "fingerprint" => fingerprint, "user_id" => @user.id }
          raise Goal::AllocationError.new(:conversion_confirmation_required)
        end
      end

      changes = proposal[:changes].map do |change|
        goal = @goals.fetch(change[:goal_id])
        account = @accounts_by_id.fetch(change[:account_id])
        link = GoalAccount.find_or_initialize_by(goal: goal, account: account)
        link.reservation_audit_managed = true
        link.update!(allocated_amount: change[:after_amount])
        goal.touch
        { account_id: account.id, goal_id: goal.id, account_name: account.name, goal_name: goal.name,
          currency: account.currency, before_amount: change[:before_amount], after_amount: change[:after_amount],
          delta: change[:before_amount].nil? ? nil : BigDecimal(change[:after_amount]) - BigDecimal(change[:before_amount]) }
      end

      @accounts.each do |account|
        if @floors.key?(account.id)
          before = account.goal_operating_floor
          after = @floors.fetch(account.id)
          changes << { account_id: account.id, account_name: account.name, currency: account.currency,
                       before_amount: before, after_amount: after, delta: after - before }
        end
        account.update_columns(goal_operating_floor: @floors.fetch(account.id, account.goal_operating_floor),
                               goal_allocation_version: account.goal_allocation_version + 1)
      end

      result = { idempotency_key: @key, accounts: @accounts.map { |account| Goal::CashReservation.new(account.reload, user: @user).as_json },
                 changes: proposal[:changes] }.deep_stringify_keys
      batch = @user.family.goal_allocations.create!(
        user: @user, idempotency_key: @key, payload_fingerprint: fingerprint, reason: @reason,
        kind: @kind, goal_funding_run_id: @funding_run&.id, result: result
      )
      changes.each { |change| batch.allocation_changes.create!(change) }
      ids = @accounts.map(&:id)
      ActiveRecord.after_all_transactions_commit { ids.each { |id| GoalFundingJob.enqueue(id) } }
    end
    result
  rescue ActiveRecord::RecordNotUnique
    prior = find_prior
    raise unless prior
    replay(prior)
  end

  def self.with_account_locks(ids)
    Account.transaction(requires_new: true) do
      ids.sort.each { |id| Goal.lock_whole_account_claims!(id) }
      Account.where(id: ids).order(:id).lock.load
      yield
    end
  end

  private
    def load_records!(lock: false)
      ids = (@operations.map { |op| op["account_id"] } + @floors.keys).uniq.sort
      raise Goal::AllocationError.new(:invalid_adjustment) if ids.size > 10
      scope = Goal::FundingAccess.accounts(@user, write: true).where(accountable_type: "Depository", id: ids).order(:id)
      @accounts = scope.to_a
      raise ActiveRecord::RecordNotFound unless @accounts.map(&:id).sort == ids
      @accounts_by_id = @accounts.index_by(&:id)

      goal_ids = @operations.map { |op| op["goal_id"] }.uniq.sort
      goals = Goal::FundingAccess.goals(@user, write: true).where(id: goal_ids).order(:id)
      goals = goals.lock if lock
      @goals = goals.index_by(&:id)
      raise ActiveRecord::RecordNotFound unless @goals.keys.sort == goal_ids
      GoalAccount.where(account_id: ids).order(:account_id, :goal_id).lock.load if lock
    end

    def check_versions!
      @accounts.each do |account|
        expected = Integer(@versions.fetch(account.id).to_s, 10)
        raise Goal::AllocationError.new(:stale_state, status: :conflict) unless expected == account.goal_allocation_version
      end
    rescue ArgumentError, KeyError
      raise Goal::AllocationError.new(:version_required)
    end

    def project
      changes = []
      reason = nil
      conversion = false
      @operations.each do |operation|
        goal = @goals.fetch(operation["goal_id"])
        account = @accounts_by_id.fetch(operation["account_id"])
        raise Goal::AllocationError.new(:goal_not_fundable) if Goal::RELEASED_STATES.include?(goal.state) || goal.currency != account.currency
        link = goal.goal_accounts.find_by(account: account)
        before = link ? link.allocated_amount : 0.to_d
        amount = BigDecimal(operation["amount"])
        if before.nil?
          raise Goal::AllocationError.new(:conversion_requires_exact_amount) unless operation["mode"] == "set"
          conversion = true
        end
        after = case operation["mode"]
        when "set" then amount
        when "add" then before + amount
        when "release" then before - amount
        end
        raise Goal::AllocationError.new(:exceeds_reservation) if after.negative?
        changes << { goal_id: goal.id, account_id: account.id,
                     before_amount: before&.to_s("F"), after_amount: after.to_s("F") }
      end

      summaries = @accounts.map do |account|
        snapshot = Goal::CashReservation.new(account, user: @user)
        replacements = changes.select { |change| change[:account_id] == account.id }.index_by { |change| change[:goal_id] }
        amounts = snapshot.links.to_h { |link| [ link.goal_id, link.allocated_amount ] }
        replacements.each { |id, change| amounts[id] = BigDecimal(change[:after_amount]) }
        after_total = amounts.values.compact.sum(0.to_d)
        floor = @floors.fetch(account.id, account.goal_operating_floor)
        increase = after_total + floor > snapshot.fixed_total + account.goal_operating_floor
        converted = replacements.values.any? { |change| change[:before_amount].nil? }
        if increase || converted
          reason ||= snapshot.review_reason unless snapshot.review_reason == "whole_account_conversion_required"
          reason ||= "whole_account_conversion_required" if amounts.values.any?(&:nil?)
          reason ||= "insufficient_cash" if snapshot.cash && after_total + floor > snapshot.cash
        end
        snapshot.as_json.merge(proposed_reserved: after_total.to_s("F"), proposed_operating_floor: floor.to_s("F"),
                               proposed_unallocated: snapshot.cash && [ snapshot.cash - after_total - floor, 0.to_d ].max.to_s("F"))
      end
      { allowed: reason.nil?, reason_code: reason, changes: changes, accounts: summaries,
        requires_conversion: conversion, versions: @versions }
    end

    def fingerprint
      Digest::SHA256.hexdigest(JSON.generate([ @user.id, @operations, @floors.sort.map { |id, value| [ id, value.to_s("F") ] }, @versions.sort, @reason, @kind ]))
    end

    def verifier
      Rails.application.message_verifier("goal-allocation-preview")
    end

    def find_prior
      @user.family.goal_allocations.find_by(idempotency_key: @key)
    end

    def replay(prior)
      unless prior.user_id == @user.id && prior.payload_fingerprint == fingerprint
        raise Goal::AllocationError.new(:idempotency_mismatch, status: :conflict)
      end
      ids = prior.result.fetch("accounts", []).flat_map { |account| account.fetch("reservations", []).filter_map { |item| item["goal_id"] } }
      existing = Goal.where(id: ids).pluck(:id)
      raise ActiveRecord::RecordNotFound if (existing - Goal::FundingAccess.goals(@user).where(id: ids).pluck(:id)).any?
      prior.result
    end
end
