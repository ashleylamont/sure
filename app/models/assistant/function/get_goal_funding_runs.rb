class Assistant::Function::GetGoalFundingRuns < Assistant::Function::GoalFunding
  PROPERTIES = { plan_id: Goal::FundingSchema::ID }.freeze
  REQUIRED = %w[plan_id].freeze

  def self.name
    "get_goal_funding_runs"
  end

  def self.description
    "Read the latest 100 funding runs for one of your plans, including wait and review reasons."
  end
end
