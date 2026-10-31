require_relative "goal_funding_test_helpers"

module GoalFundingApiHelpers
  include GoalFundingTestHelpers

  def setup_funding_api
    setup_funding_context
    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(user: @user, name: "Funding test", scopes: %w[read_write], source: "web", display_key: "funding_#{SecureRandom.hex(16)}")
    @read_key = ApiKey.create!(user: @user, name: "Read funding test", scopes: %w[read], source: "mobile", display_key: "funding_read_#{SecureRandom.hex(16)}")
  end

  def api_headers(key = @api_key)
    { "X-Api-Key" => key.display_key }
  end

  def allocation_body
    { allocation: { adjustments: [ { goal_id: @etf.id, account_id: @cash.id, mode: "add", amount: "150" } ],
                    versions: { @cash.id => @cash.reload.goal_allocation_version }, idempotency_key: "api-allocation", reason: "User reviewed" } }
  end

  def plan_body
    { plan: { name: "Salary funding", backing_account_id: @cash.id, sample_entry_id: @sample.id,
      minimum_salary: "4000", maximum_salary: "4000", effective_on: "2026-11-02",
      rules: [ { goal_id: @etf.id, amount: "150" }, { goal_id: @giving.id, amount: "100" } ] } }
  end
end
