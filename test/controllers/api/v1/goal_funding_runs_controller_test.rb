require "test_helper"
require_relative "../../../support/goal_funding_api_helpers"

class Api::V1::GoalFundingRunsControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingApiHelpers
  setup do
    setup_funding_api
    @plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    @run = @plan.process_source!(salary_entry)
  end
  teardown { travel_back }

  test "read and reverse an applied run with a reviewed token" do
    get api_v1_goal_funding_plan_goal_funding_runs_url(@plan), headers: api_headers(@read_key)
    assert_response :success
    assert_equal @run.id, response.parsed_body["runs"].first["id"]
    get api_v1_goal_funding_run_url(@run), headers: api_headers
    assert_response :success
    get preview_api_v1_goal_funding_run_url(@run, operation: "reverse"), headers: api_headers
    assert_response :success
    post reverse_api_v1_goal_funding_run_url(@run), headers: api_headers, as: :json, params: { preview_token: response.parsed_body["preview_token"] }
    assert_response :success
    assert_equal "reversed", response.parsed_body["status"]
    assert_equal 0, allocation_for(@etf)
  end

  test "retry requires preview and skipped runs cannot apply" do
    @cash.update!(balance: 1250)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 27, 12)
    waiting = @plan.process_source!(salary_entry)
    post retry_api_v1_goal_funding_run_url(waiting), headers: api_headers
    assert_response :conflict
    get preview_api_v1_goal_funding_run_url(waiting), headers: api_headers
    assert_response :success
    post retry_api_v1_goal_funding_run_url(waiting), headers: api_headers, as: :json, params: { preview_token: response.parsed_body["preview_token"] }
    assert_response :success
    assert_equal "awaiting_funds", response.parsed_body["status"]
    post skip_api_v1_goal_funding_run_url(waiting), headers: api_headers
    assert_response :success
    assert_equal "skipped", response.parsed_body["status"]
  end

  test "scope tenant and authentication boundaries protect run details" do
    post skip_api_v1_goal_funding_run_url(@run), headers: api_headers(@read_key)
    assert_response :forbidden
    get api_v1_goal_funding_run_url(@run)
    assert_response :unauthorized
    get api_v1_goal_funding_run_url(SecureRandom.uuid), headers: api_headers
    assert_response :not_found
    @cash.update!(owner: users(:family_member))
    get api_v1_goal_funding_run_url(@run), headers: api_headers
    assert_response :not_found
  end

  test "another family cannot read or mutate a goal plan or run" do
    outsider = users(:empty)
    outsider.update!(preferences: outsider.preferences.merge("preview_features_enabled" => true))
    outsider.api_keys.active.destroy_all
    key = ApiKey.create!(user: outsider, name: "Other family", scopes: %w[read_write], source: "web", display_key: "other_#{SecureRandom.hex(16)}")
    [ api_v1_goal_url(@etf), api_v1_goal_funding_plan_url(@plan), api_v1_goal_funding_run_url(@run) ].each do |url|
      get url, headers: api_headers(key)
      assert_response :not_found
      assert_not_includes response.body, @etf.name
    end
    post skip_api_v1_goal_funding_run_url(@run), headers: api_headers(key)
    assert_response :not_found
    assert_equal "applied", @run.reload.status
  end
end
