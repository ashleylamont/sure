class Goal::CashReservation
  attr_reader :account, :user

  def initialize(account, user:)
    @account, @user = account, user
  end

  def links
    @links ||= account.goal_accounts.joins(:goal)
      .where.not(goals: { state: Goal::RELEASED_STATES }).includes(:goal).order(:id).to_a
  end

  def fixed_total
    links.sum(0.to_d) { |link| link.allocated_amount.to_d }
  end

  def whole_account_links
    links.select(&:whole_account?)
  end

  def cash
    return nil unless account.goal_cash_reconciled_at && account.goal_reconciled_cash
    [ account.goal_reconciled_cash, account.balance ].min.to_d
  end

  def review_reason
    return "cash_not_reconciled" unless cash
    return "pending_cash" if account.entries.pending.exists?
    return "cash_sync_incomplete" if account.syncs.incomplete.exists?
    "whole_account_conversion_required" if whole_account_links.any?
  end

  def unallocated
    return 0.to_d if review_reason
    [ cash - fixed_total - account.goal_operating_floor, 0.to_d ].max
  end

  def shortage
    return 0.to_d unless cash
    [ fixed_total + account.goal_operating_floor - cash, 0.to_d ].max
  end

  def as_json(*)
    visible_goals = Goal::FundingAccess.goals(user).where(id: links.map(&:goal_id)).pluck(:id).to_set
    {
      account_id: account.id, account_name: account.name, currency: account.currency,
      cash: cash&.to_s("F"), reconciled_at: account.goal_cash_reconciled_at&.iso8601,
      operating_floor: account.goal_operating_floor.to_s("F"),
      fixed_reserved: fixed_total.to_s("F"), unallocated: unallocated.to_s("F"),
      shortage: shortage.to_s("F"), version: account.goal_allocation_version,
      review_reason: review_reason,
      reservations: links.map do |link|
        visible = visible_goals.include?(link.goal_id)
        { goal_id: visible ? link.goal_id : nil,
          goal_name: visible ? link.goal.name : I18n.t("goal_funding.private_purpose"),
          reserved: link.allocated_amount&.to_s("F"), whole_account: link.whole_account?,
          state: visible ? link.goal.state : nil }
      end
    }
  end

  def self.record_reconciliation!(account, at: Time.current)
    return unless account.accountable_type == "Depository"
    Account.transaction do
      Goal.lock_whole_account_claims!(account.id)
      account.lock!
      return if account.syncs.incomplete.exists?
      account.update_columns(goal_reconciled_cash: account.balance,
                             goal_cash_reconciled_at: at,
                             goal_allocation_version: account.goal_allocation_version + 1)
    end
  end
end
