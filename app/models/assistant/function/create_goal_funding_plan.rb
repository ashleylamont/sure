class Assistant::Function::CreateGoalFundingPlan < Assistant::Function::GoalFunding
  PROPERTIES = { plan: Goal::FundingSchema::PLAN }.freeze
  REQUIRED = %w[plan].freeze

  def self.name
    "create_goal_funding_plan"
  end

  def self.description
    "Create a disabled fixed-contribution plan from a real ordinary salary sample. Ask the user to verify this descriptor and amount range exclude equity/bonus deposits. Preview, then explicitly enable separately."
  end
end
