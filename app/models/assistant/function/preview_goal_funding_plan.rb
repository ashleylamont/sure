class Assistant::Function::PreviewGoalFundingPlan < Assistant::Function::GoalFunding
  PROPERTIES = { plan_id: Goal::FundingSchema::ID }.freeze
  REQUIRED = %w[plan_id].freeze

  def self.name
    "preview_goal_funding_plan"
  end

  def self.description
    "Read-only preview of the matched salary, protected reservations, exact proposed contributions and remaining cash. Returns a short-lived token required for enabling."
  end
end
