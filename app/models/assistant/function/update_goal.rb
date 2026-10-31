class Assistant::Function::UpdateGoal < Assistant::Function::GoalFunding
  PROPERTIES = { goal_id: Goal::FundingSchema::ID, goal: Goal::FundingSchema::GOAL }.freeze
  REQUIRED = %w[goal_id goal].freeze

  def self.name
    "update_goal"
  end

  def self.description
    "Update a visible goal after user confirmation. Pass its version; allocation writes also require account versions, a reason and idempotency key."
  end
end
