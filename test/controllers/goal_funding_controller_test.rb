require "test_helper"
require_relative "../support/goal_funding_test_helpers"

class GoalFundingControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingTestHelpers
  setup do
    setup_funding_context
    sign_in @user
  end
  teardown { travel_back }

  test "funding pages show protected cash and a disabled draft preview" do
    plan = funding_plan(enable: false)
    [ goal_funding_url, new_goal_allocation_url, new_goal_funding_plan_url, edit_goal_funding_plan_url(plan), goal_funding_plan_url(plan) ].each do |url|
      get url
      assert_response :success
    end
    assert_select "label", text: /I verified the sample/
    assert_select "input[name=preview_token]"
    assert_not plan.reload.enabled?
  end

  test "manual move previews before applying" do
    data = { allocation: { account_id: @cash.id, goal_id: @protected_goal.id, destination_goal_id: @giving.id,
      mode: "move", amount: "80", version: @cash.reload.goal_allocation_version, idempotency_key: "web-move", reason: "Card purchase" } }
    post preview_goal_allocations_url, params: data
    assert_response :success
    assert_equal 1000, allocation_for(@protected_goal)
    data[:allocation][:preview_token] = css_select("input[name='allocation[preview_token]']").first["value"]
    post goal_allocations_url, params: data
    assert_redirected_to goal_funding_url
    assert_equal 920, allocation_for(@protected_goal)
    assert_equal 80, allocation_for(@giving)
  end

  test "non-preview users cannot access funding" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    get goal_funding_url
    assert_redirected_to root_url
  end
end
