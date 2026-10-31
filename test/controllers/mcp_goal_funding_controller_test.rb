require "test_helper"
require_relative "../support/goal_funding_test_helpers"

class McpGoalFundingControllerTest < ActionDispatch::IntegrationTest
  include GoalFundingTestHelpers
  setup do
    setup_funding_context
    application = Doorkeeper::Application.create!(name: "Funding MCP test", redirect_uri: "https://example.com/callback", confidential: false)
    @token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: "read_write", expires_in: 1.hour)
  end
  teardown { travel_back }

  test "normal MCP OAuth registry exposes and calls the funding tools" do
    rpc("tools/list")
    assert_response :success
    names = response.parsed_body.fetch("result").fetch("tools").map { |tool| tool.fetch("name") }
    assert_includes names, "adjust_goal_allocations"
    assert_includes names, "enable_goal_funding_plan"
    rpc("tools/call", { name: "get_goals", arguments: {} })
    assert_response :success
    data = JSON.parse(response.parsed_body.fetch("result").fetch("content").first.fetch("text"))
    assert_includes data.fetch("goals").map { |goal| goal.fetch("id") }, @etf.id
    rpc("tools/call", { name: "update_goal", arguments: { goal_id: SecureRandom.uuid, goal: {} } })
    data = JSON.parse(response.parsed_body.fetch("result").fetch("content").first.fetch("text"))
    assert_equal "not_found", data["error"]
  end

  private
    def rpc(method, params = {})
      post "/mcp", params: { jsonrpc: "2.0", method: method, params: params, id: 1 }.to_json,
        headers: { "Authorization" => "Bearer #{@token.token}", "Content-Type" => "application/json" }
    end
end
