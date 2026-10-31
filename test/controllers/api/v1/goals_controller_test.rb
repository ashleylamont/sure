require "test_helper"
require_relative "../../../support/goal_funding_api_helpers"

class Api::V1::GoalsControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingApiHelpers
  setup { setup_funding_api }
  teardown { travel_back }

  test "lists goals and true cash reservations with a read key" do
    get api_v1_goals_url, headers: api_headers(@read_key)
    assert_response :success
    assert_includes response.parsed_body["goals"].map { |goal| goal["id"] }, @etf.id
    assert_equal "1000.0", response.parsed_body["accounts"].find { |account| account["account_id"] == @cash.id }["fixed_reserved"]
    get api_v1_goal_url(@etf), headers: api_headers
    assert_response :success
    assert_equal "maintained", response.parsed_body["kind"]
  end

  test "creates updates and deletes a goal using account and goal versions" do
    post api_v1_goals_url, headers: api_headers, as: :json, params: { goal: {
      name: "Emergency reserve", kind: "maintained", target_amount: "5000", currency: "USD",
      allocations: [ { account_id: @cash.id, amount: "100" } ], versions: { @cash.id => @cash.reload.goal_allocation_version },
      idempotency_key: "opening", reason: "Opening reserve" } }
    assert_response :created
    id = response.parsed_body["id"]
    version = response.parsed_body["version"]
    patch api_v1_goal_url(id), headers: api_headers, as: :json, params: { goal: { name: "Emergency cash", version: version } }
    assert_response :success
    assert_equal "Emergency cash", response.parsed_body["name"]
    delete api_v1_goal_url(id), headers: api_headers, as: :json, params: { version: response.parsed_body["version"] }
    assert_response :no_content
    assert GoalAllocationChange.where(goal_id: id).exists?, "Deleted goals retain their reservation audit"
  end

  test "auth scope preview access and private accounts are enforced" do
    get api_v1_goals_url
    assert_response :unauthorized
    patch api_v1_goal_url(@etf), headers: api_headers(@read_key), as: :json, params: { goal: { name: "No" } }
    assert_response :forbidden
    get api_v1_goal_url(SecureRandom.uuid), headers: api_headers
    assert_response :not_found
    @cash.update!(owner: users(:family_member))
    get api_v1_goal_url(@etf), headers: api_headers
    assert_response :not_found
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    get api_v1_goals_url, headers: api_headers
    assert_response :forbidden
  end

  test "invalid parameters dates and stale versions do not change goals" do
    patch api_v1_goal_url(@etf), headers: api_headers, as: :json, params: { goal: { name: "Stale", version: "old" } }
    assert_response :conflict
    patch api_v1_goal_url(@etf), headers: api_headers, as: :json, params: { goal: { target_amount: "-1", version: @etf.updated_at.iso8601(6) } }
    assert_response :unprocessable_entity
    patch api_v1_goal_url(@etf), headers: api_headers, as: :json, params: { goal: { target_date: "not-a-date", version: @etf.reload.updated_at.iso8601(6) } }
    assert_response :unprocessable_entity
  end
end
