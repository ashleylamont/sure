class Assistant::Function::GetGoalFundingPlans < Assistant::Function::GoalFunding
  PROPERTIES = {}.freeze
  REQUIRED = [].freeze

  def self.name
    "get_goal_funding_plans"
  end

  def self.description
    "Read your accessible payday funding plans and their revisions."
  end
end
