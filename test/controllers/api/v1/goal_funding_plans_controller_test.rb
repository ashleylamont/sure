require "test_helper"
require_relative "../../../support/goal_funding_api_helpers"

class Api::V1::GoalFundingPlansControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingApiHelpers
  setup { setup_funding_api }
  teardown { travel_back }

  test "create read preview update enable and disable a draft plan" do
    post api_v1_goal_funding_plans_url, headers: api_headers, as: :json, params: plan_body
    assert_response :created
    id = response.parsed_body["id"]
    assert_equal false, response.parsed_body["enabled"]
    get api_v1_goal_funding_plans_url, headers: api_headers(@read_key)
    assert_response :success
    get api_v1_goal_funding_plan_url(id), headers: api_headers(@read_key)
    assert_response :success
    revision = response.parsed_body["revision"]
    patch api_v1_goal_funding_plan_url(id), headers: api_headers, as: :json, params: { plan: { name: "Revised", revision: revision } }
    assert_response :success
    assert_no_difference "GoalFundingRun.count" do
      get preview_api_v1_goal_funding_plan_url(id), headers: api_headers(@read_key)
      assert_response :success
    end
    post enable_api_v1_goal_funding_plan_url(id), headers: api_headers, as: :json,
      params: { preview_token: response.parsed_body["preview_token"], confirm_salary_source: true }
    assert_response :success
    assert_equal true, response.parsed_body["enabled"]
    post disable_api_v1_goal_funding_plan_url(id), headers: api_headers
    assert_response :success
    assert_equal false, response.parsed_body["enabled"]
  end

  test "authorization invalid dates and stale revisions are rejected" do
    plan = funding_plan(enable: false)
    get api_v1_goal_funding_plan_url(plan)
    assert_response :unauthorized
    post enable_api_v1_goal_funding_plan_url(plan), headers: api_headers(@read_key)
    assert_response :forbidden
    patch api_v1_goal_funding_plan_url(plan), headers: api_headers, as: :json, params: { plan: { revision: 0, name: "Stale" } }
    assert_response :conflict
    data = plan_body
    data[:plan][:effective_on] = "invalid"
    post api_v1_goal_funding_plans_url, headers: api_headers, as: :json, params: data
    assert_response :unprocessable_entity
    @cash.update!(owner: users(:family_member))
    get api_v1_goal_funding_plan_url(plan), headers: api_headers
    assert_response :not_found
    get api_v1_goal_funding_plan_url(SecureRandom.uuid), headers: api_headers
    assert_response :not_found
  end
end
