require "test_helper"
require_relative "../../../support/goal_funding_test_helpers"

class Assistant::Function::GoalFundingTest < ActiveSupport::TestCase
  include GoalFundingTestHelpers
  setup { setup_funding_context }
  teardown { travel_back }

  test "funding tools are available through the normal preview registry" do
    tools = Assistant.function_classes(@user).map(&:name)
    %w[get_goals update_goal adjust_goal_allocations get_goal_funding_plans get_goal_funding_runs create_goal_funding_plan update_goal_funding_plan preview_goal_funding_plan enable_goal_funding_plan disable_goal_funding_plan review_goal_funding_run].each do |name|
      assert_includes tools, name
      klass = Assistant.function_classes(@user).find { |candidate| candidate.name == name }
      assert_equal "object", klass.new(@user).params_schema[:type]
    end
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    assert_not_includes Assistant.function_classes(@user).map(&:name), "get_goal_funding_plans"
    assert_equal "preview_disabled", Assistant::Function::GetGoals.new(@user).call[:error]
  end

  test "maintained create and update use explicit reservations and versions" do
    result = Assistant::Function::CreateGoal.new(@user).call("name" => "Emergency", "kind" => "maintained", "target_amount" => "5000",
      "linked_account_names" => [ @cash.name ], "earmarks" => { @cash.name => "100" },
      "versions" => { @cash.id => @cash.reload.goal_allocation_version }, "idempotency_key" => "mcp-opening", "reason" => "Opening emergency cash")
    assert result[:success], result.inspect
    goal = Goal.find(result[:goal_id])
    assert_equal "maintained", goal.kind
    assert_equal 100, allocation_for(goal)
    response = Assistant::Function::UpdateGoal.new(@user).call("goal_id" => goal.id, "goal" => { "name" => "Emergency cash", "version" => goal.updated_at.iso8601(6) })
    assert_equal "Emergency cash", response[:name]
    assert_equal 100, allocation_for(goal)
  end

  test "allocation tool previews by default and applies the identical reviewed request once" do
    params = { "adjustments" => [ { "goal_id" => @etf.id, "account_id" => @cash.id, "amount" => "150", "mode" => "add" } ],
      "idempotency_key" => "mcp-allocation", "reason" => "Confirmed investment reserve", "versions" => { @cash.id => @cash.reload.goal_allocation_version } }
    tool = Assistant::Function::AdjustGoalAllocations.new(@user)
    preview = tool.call(params)
    assert preview[:allowed]
    assert_equal 0, allocation_for(@etf)
    params.merge!("apply" => true, "preview_token" => preview[:preview_token])
    2.times { assert tool.call(params)["changes"] }
    assert_equal 150, allocation_for(@etf)
  end

  test "create preview enable list update and disable a plan through tools" do
    created = Assistant::Function::CreateGoalFundingPlan.new(@user).call("plan" => {
      "name" => "Ordinary payroll", "backing_account_id" => @cash.id, "sample_entry_id" => @sample.id,
      "minimum_salary" => "4000", "maximum_salary" => "4000", "effective_on" => "2026-11-02",
      "rules" => [ { "goal_id" => @etf.id, "amount" => "150" }, { "goal_id" => @giving.id, "amount" => "100" } ] })
    assert_equal false, created["enabled"], created.inspect
    id = created["id"]
    preview = Assistant::Function::PreviewGoalFundingPlan.new(@user).call("plan_id" => id)
    enabled = Assistant::Function::EnableGoalFundingPlan.new(@user).call("plan_id" => id, "preview_token" => preview[:preview_token], "confirm_salary_source" => true)
    assert_equal true, enabled["enabled"]
    assert_includes Assistant::Function::GetGoalFundingPlans.new(@user).call[:plans].map { |plan| plan["id"] }, id
    travel_to Time.utc(2026, 11, 12, 12)
    GoalFundingPlan.find(id).process_source!(salary_entry)
    assert_equal "applied", Assistant::Function::GetGoalFundingRuns.new(@user).call("plan_id" => id)[:runs].first["status"]
    updated = Assistant::Function::UpdateGoalFundingPlan.new(@user).call("plan_id" => id, "revision" => enabled["revision"], "plan" => { "name" => "Revised" })
    assert_equal false, updated["enabled"]
    assert_equal false, Assistant::Function::DisableGoalFundingPlan.new(@user).call("plan_id" => id)[:enabled]
  end

  test "private accounts foreign goals guests and inactive users cannot mutate funding" do
    plan = funding_plan
    @cash.update!(owner: users(:family_member))
    assert_equal "not_found", Assistant::Function::PreviewGoalFundingPlan.new(@user).call("plan_id" => plan.id)[:error]
    assert_equal "not_found", Assistant::Function::UpdateGoal.new(@user).call("goal_id" => @etf.id, "goal" => {})[:error]
    assert_not_includes Assistant::Function::GetGoals.new(@user).call[:goals].map { |goal| goal[:id] }, @etf.id
    @user.update!(role: "guest")
    assert_not_includes Assistant.function_classes(@user).map(&:name), "create_goal_funding_plan"
    assert_equal "forbidden", Assistant::Function::CreateGoal.new(@user).call("name" => "No")[:error]
  end
end
