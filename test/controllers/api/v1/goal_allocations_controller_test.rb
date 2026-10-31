require "test_helper"
require_relative "../../../support/goal_funding_api_helpers"

class Api::V1::GoalAllocationsControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingApiHelpers
  setup { setup_funding_api }
  teardown { travel_back }

  test "preview is read only and apply is atomic and replayable" do
    data = allocation_body
    assert_no_difference [ "GoalAllocation.count", "GoalAllocationChange.count" ] do
      post preview_api_v1_goal_allocations_url, headers: api_headers, as: :json, params: data
      assert_response :success
    end
    2.times do
      post api_v1_goal_allocations_url, headers: api_headers, as: :json, params: data
      assert_response :success
    end
    assert_equal 150, allocation_for(@etf)
    data[:allocation][:adjustments][0][:amount] = "151"
    post api_v1_goal_allocations_url, headers: api_headers, as: :json, params: data
    assert_response :conflict
    assert_equal "idempotency_mismatch", response.parsed_body["error"]
  end

  test "read scope missing auth invalid money and foreign goals fail safely" do
    post api_v1_goal_allocations_url, headers: api_headers(@read_key), as: :json, params: allocation_body
    assert_response :forbidden
    post api_v1_goal_allocations_url, as: :json, params: allocation_body
    assert_response :unauthorized
    data = allocation_body
    data[:allocation][:adjustments][0][:amount] = "NaN"
    post api_v1_goal_allocations_url, headers: api_headers, as: :json, params: data
    assert_response :unprocessable_entity
    data[:allocation][:adjustments][0].merge!(goal_id: SecureRandom.uuid, amount: "1")
    post api_v1_goal_allocations_url, headers: api_headers, as: :json, params: data
    assert_response :not_found
  end
end
