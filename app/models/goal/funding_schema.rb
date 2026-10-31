class Goal::FundingSchema
  MONEY = { type: "string", pattern: "^\\d+(\\.\\d{1,4})?$", description: "Exact nonnegative amount in the account currency; at most four decimal places." }.freeze
  ID = { type: "string", format: "uuid" }.freeze
  RULE = { type: "object", additionalProperties: false, required: %w[goal_id amount], properties: {
    goal_id: ID, amount: MONEY, stop_at_target: { type: "boolean" }
  } }.freeze
  ADJUSTMENT = { type: "object", additionalProperties: false, required: %w[goal_id account_id amount], properties: {
    goal_id: ID, account_id: ID, amount: MONEY, mode: { type: "string", enum: %w[set add release] }
  } }.freeze
  ALLOCATION = { type: "object", additionalProperties: false, required: %w[account_id amount], properties: {
    account_id: ID, amount: MONEY, mode: { type: "string", enum: %w[set add release] }
  } }.freeze
  VERSIONS = { type: "object", additionalProperties: { type: "integer" }, description: "Account UUID to version from get_goals/preview. Required when applying." }.freeze
  PLAN = { type: "object", additionalProperties: false, properties: {
    name: { type: "string" }, revision: { type: "integer" }, backing_account_id: ID, sample_entry_id: ID,
    source_name: { type: "string", description: "Exact ordinary-payroll description; never just an employer name shared with equity payments." },
    source_notes: { type: "string" }, minimum_salary: MONEY, maximum_salary: MONEY,
    effective_on: { type: "string", format: "date" }, rules: { type: "array", minItems: 1, maxItems: 30, items: RULE }
  } }.freeze
  GOAL = { type: "object", additionalProperties: false, properties: {
    name: { type: "string" }, kind: { type: "string", enum: %w[one_off maintained] },
    target_mode: { type: "string", enum: %w[fixed months_of_expenses] }, target_amount: MONEY,
    target_months: { type: "number" }, target_date: { type: "string", format: "date" },
    notes: { type: "string" }, color: { type: "string" }, icon: { type: "string" }, currency: { type: "string" },
    allocations: { type: "array", items: ALLOCATION }, versions: VERSIONS,
    idempotency_key: { type: "string" }, reason: { type: "string" }, version: { type: "string" }
  } }.freeze
end
