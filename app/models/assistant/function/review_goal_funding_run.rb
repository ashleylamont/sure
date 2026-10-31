class Assistant::Function::ReviewGoalFundingRun < Assistant::Function::GoalFunding
  PROPERTIES = { run_id: Goal::FundingSchema::ID, operation: { type: "string", enum: %w[preview_retry preview_reverse retry skip reverse] }, preview_token: { type: "string" } }.freeze
  REQUIRED = %w[run_id operation].freeze

  def self.name
    "review_goal_funding_run"
  end

  def self.description
    "Preview a retry or compensating reversal first. Retry/reverse require the returned token and explicit user confirmation. Applied runs cannot be retried or skipped. Reversal releases only cash still reserved; it never reverses bank money."
  end
end
