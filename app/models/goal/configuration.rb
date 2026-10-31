class Goal::Configuration
  FIELDS = %w[name kind target_mode target_amount target_months target_date notes color icon currency].freeze

  def initialize(user, goal = nil)
    @user = user
    @goal = goal || user.family.goals.new(color: Goal::COLORS.first, currency: user.family.primary_currency_code)
  end

  def save!(attributes:, allocations: nil, versions: {}, idempotency_key: nil, reason: nil, version: nil)
    Goal::FundingAccess.accounts(@user, write: true)
    Goal.transaction(requires_new: true) do
      account_ids = allocations ? Array(allocations).map { |item| item.to_h.stringify_keys.fetch("account_id") } : @goal.goal_accounts.pluck(:account_id)
      Goal::AllocationAdjustment.with_account_locks(account_ids.uniq) do
        if @goal.persisted?
          Goal::FundingAccess.goals(@user, write: true).find(@goal.id)
          @goal.lock!
          raise Goal::AllocationError.new(:stale_state, status: :conflict) unless version == @goal.updated_at.iso8601(6)
        end
        values = attributes.to_h.stringify_keys.slice(*FIELDS)
        values["target_date"] = Date.iso8601(values["target_date"]) if values["target_date"].present?
        values["target_amount"] = Goal::FundingAccess.decimal(values["target_amount"], positive: true) if values.key?("target_amount")
        @goal.assign_attributes(values)
        @goal.currency ||= @user.family.primary_currency_code
        if @goal.new_record?
          raise Goal::AllocationError.new(:linked_accounts_required) if allocations.blank?
          accounts = Goal::FundingAccess.accounts(@user, write: true).where(accountable_type: "Depository", id: account_ids).index_by(&:id)
          raise ActiveRecord::RecordNotFound unless accounts.keys.sort == account_ids.uniq.sort
          account_ids.uniq.each { |id| @goal.goal_accounts.build(account: accounts.fetch(id), allocated_amount: 0, reservation_audit_managed: true) }
        end
        # Link construction is a zero opening projection; the versioned writer below
        # records and checks the requested opening reservation in this transaction.
        @goal.save!
        if allocations
          # Allocation changes always go through the versioned cash checks; omitted links stay reserved.
          operations = Array(allocations).map { |item| item.to_h.stringify_keys.slice("account_id", "amount", "mode").merge("goal_id" => @goal.id) }
          Goal::AllocationAdjustment.new(user: @user, adjustments: operations, versions: versions,
            idempotency_key: idempotency_key, reason: reason).apply!
        end
      end
    end
    @goal.reload
  end
end
