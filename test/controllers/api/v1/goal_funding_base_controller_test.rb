require "test_helper"
require_relative "../../../support/goal_funding_api_helpers"

class Api::V1::GoalFundingBaseControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingApiHelpers
  setup { setup_funding_api }
  teardown { travel_back }

  test "funding endpoints require authentication preview access and non-guest writes" do
    get api_v1_goals_url
    assert_response :unauthorized
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    get api_v1_goals_url, headers: api_headers
    assert_response :forbidden
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true), role: "guest")
    get api_v1_goals_url, headers: api_headers(@read_key)
    assert_response :success
    assert_no_difference "Goal.count" do
      post api_v1_goals_url, headers: api_headers, as: :json, params: { goal: { name: "Refused", target_amount: "100" } }
      assert_response :forbidden
    end
  end
end
