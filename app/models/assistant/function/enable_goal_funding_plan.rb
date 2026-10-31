class Assistant::Function::EnableGoalFundingPlan < Assistant::Function::GoalFunding
  PROPERTIES = { plan_id: Goal::FundingSchema::ID, preview_token: { type: "string" }, confirm_salary_source: { type: "boolean" } }.freeze
  REQUIRED = %w[plan_id preview_token confirm_salary_source].freeze

  def self.name
    "enable_goal_funding_plan"
  end

  def self.description
    "Enable only after showing the preview and obtaining explicit user approval of salary matching and contributions. Future dated salaries start no earlier than the next family-local day; historical salaries are never backfilled."
  end
end
