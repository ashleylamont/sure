class Assistant::Function::DisableGoalFundingPlan < Assistant::Function::GoalFunding
  PROPERTIES = { plan_id: Goal::FundingSchema::ID }.freeze
  REQUIRED = %w[plan_id].freeze

  def self.name
    "disable_goal_funding_plan"
  end

  def self.description
    "Stop new funding without releasing reservations or deleting history."
  end
end
