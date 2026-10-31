class Assistant::Function::UpdateGoalFundingPlan < Assistant::Function::GoalFunding
  PROPERTIES = { plan_id: Goal::FundingSchema::ID, revision: { type: "integer" }, plan: Goal::FundingSchema::PLAN }.freeze
  REQUIRED = %w[plan_id revision plan].freeze

  def self.name
    "update_goal_funding_plan"
  end

  def self.description
    "Update a plan using its current revision. Configuration changes disable automation and require a fresh preview and enable confirmation. Waiting runs retain their original payload for review."
  end
end
