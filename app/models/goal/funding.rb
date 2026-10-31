# Shared entry points for web, API and assistant callers. Account access is checked
# again by the writers while holding locks; serializations never expose hidden links.
class Goal::Funding
  attr_reader :user

  def initialize(user)
    @user = user
    raise Goal::AllocationError.new(:preview_disabled, status: :forbidden) unless user&.preview_features_enabled?
    Goal::FundingAccess.accounts(user)
  end

  def goals
    Goal::FundingAccess.goals(user).includes(goal_accounts: :account).order(:id)
  end

  def goal(id, write: false)
    Goal::FundingAccess.goals(user, write: write).find(id)
  end

  def accounts(write: false)
    Goal::FundingAccess.accounts(user, write: write).where(accountable_type: "Depository").order(:name, :id)
  end

  def plans
    GoalFundingPlan.for_user(user).includes(:rules).order(:id).select do |plan|
      plan.validate_access!
      true
    rescue Goal::AllocationError, ActiveRecord::RecordNotFound
      false
    end
  end

  def plan(id)
    record = GoalFundingPlan.for_user(user).find(id)
    record.validate_access!
    record
  end

  def run(id)
    record = GoalFundingRun.joins(:goal_funding_plan).where(goal_funding_plans: { user_id: user.id, family_id: user.family_id }).find(id)
    record.goal_funding_plan.validate_access!
    validate_run_access!(record)
    record
  end

  def runs(plan)
    plan.runs.order(created_at: :desc, id: :desc).limit(100).select do |record|
      validate_run_access!(record)
      true
    rescue ActiveRecord::RecordNotFound
      false
    end
  end

  def goal_json(record)
    { id: record.id, name: record.name, kind: record.kind, state: record.state, currency: record.currency,
      target_mode: record.target_mode, target_amount: record.target_amount.to_s("F"), target_months: record.target_months,
      target_date: record.target_date, notes: record.notes, color: record.color, icon: record.icon,
      effective_backing: record.current_balance.to_s("F"), version: record.updated_at.iso8601(6),
      allocations: record.goal_accounts.map do |link|
        { account_id: link.account_id, account_name: link.account.name, currency: link.account.currency,
          reserved: link.allocated_amount&.to_s("F"), whole_account: link.whole_account?,
          account_version: link.account.goal_allocation_version }
      end }
  end

  def plan_json(record)
    record.attributes.slice("id", "name", "backing_account_id", "source_account_id", "sample_entry_id", "currency",
      "source_name", "source_notes", "minimum_salary", "maximum_salary", "effective_on", "revision", "enabled", "enabled_at")
      .merge("automatic_start_on" => record.automatic_start_on, "rules" => record.rules.order(:goal_id).map(&:snapshot))
  end

  def run_json(record)
    record.attributes.slice("id", "goal_funding_plan_id", "source_entry_id", "source_date", "plan_revision", "rules_snapshot",
      "status", "reason_code", "applied_at", "reversed_at", "created_at", "review_history")
  end

  def save_plan(attributes:, rules:, id: nil, revision: nil)
    record = id ? plan(id) : user.family.goal_funding_plans.new(user: user)
    record.configure!(actor: user, attributes: attributes, rules: rules, expected_revision: revision)
  end

  private
    def validate_run_access!(record)
      snapshots = record.rules_snapshot + record.review_history.flat_map { |review| review["rules"] || [] }
      ids = snapshots.filter_map { |rule| rule["goal_id"] }
      existing = Goal.where(id: ids).pluck(:id)
      raise ActiveRecord::RecordNotFound if (existing - Goal::FundingAccess.goals(user).where(id: ids).pluck(:id)).any?

      account_ids = GoalAllocationChange.joins(:goal_allocation).where(goal_allocations: { goal_funding_run_id: record.id }).pluck(:account_id)
      account_ids << record.source_entry.account_id if record.source_entry
      permitted = Goal::FundingAccess.accounts(user).select(:id)
      raise ActiveRecord::RecordNotFound if Account.where(id: account_ids).where.not(id: permitted).exists?
    end
end
