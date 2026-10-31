class Assistant::Function::AdjustGoalAllocations < Assistant::Function::GoalFunding
  PROPERTIES = { adjustments: { type: "array", items: Goal::FundingSchema::ADJUSTMENT, maxItems: 30 }, versions: Goal::FundingSchema::VERSIONS, floors: { type: "object", additionalProperties: Goal::FundingSchema::MONEY }, idempotency_key: { type: "string" }, reason: { type: "string" }, apply: { type: "boolean" }, preview_token: { type: "string" }, confirm_conversion: { type: "boolean" } }.freeze
  REQUIRED = %w[adjustments idempotency_key reason].freeze

  def self.name
    "adjust_goal_allocations"
  end

  def self.description
    "Preview by default. After confirmation, apply exact set/add/release operations atomically. To move cash, release one purpose and add another in the same request. Never moves bank money. Reuse the key only for identical requests."
  end
end
