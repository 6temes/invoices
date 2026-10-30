require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  MCP_HEADERS = {
    "Accept" => "application/json, text/event-stream",
    "MCP-Protocol-Version" => "2025-06-18"
  }

  test "refuses a request without a token" do
    post mcp_path, params: initialize_request, headers: MCP_HEADERS, as: :json
    assert_response :unauthorized
  end

  test "refuses a Chrome extension token" do
    post mcp_path, params: initialize_request, headers: auth("test_token_abc123"), as: :json
    assert_response :forbidden
  end

  test "initializes with a read invoices token" do
    post mcp_path, params: initialize_request, headers: auth, as: :json

    assert_response :success
    result = response.parsed_body["result"]
    assert_equal "2025-06-18", result["protocolVersion"]
    assert_equal "invoices", result["serverInfo"]["name"]
  end

  test "accepts a notification with an empty 202" do
    post mcp_path, params: { jsonrpc: "2.0", method: "notifications/initialized" }, headers: auth, as: :json

    assert_response :accepted
    assert_empty response.body
  end

  test "answers GET with 405" do
    get mcp_path, headers: auth
    assert_response :method_not_allowed
  end

  test "records when the token was used" do
    freeze_time do
      post mcp_path, params: initialize_request, headers: auth, as: :json
      assert_equal Time.current, api_tokens(:read_invoices).reload.last_used_at
    end
  end

  test "does not block a request from another origin" do
    post mcp_path, params: initialize_request, headers: auth.merge("Origin" => "https://example.org"), as: :json
    assert_response :success
  end

  test "reports a failing tool and returns a JSON-RPC error" do
    failing_tool = MCP::Tool.define(name: "explode") { raise ArgumentError, "boom" }
    McpController.any_instance.stubs(:tools).returns([ failing_tool ])

    Rails.error.expects(:report).with { |error, **| error.is_a?(ArgumentError) }
    post mcp_path, params: { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "explode", arguments: {} } }, headers: auth, as: :json

    assert_response :success
    assert response.parsed_body["error"] || response.parsed_body.dig("result", "isError")
  end

  private

  def auth(token = "test_token_read_invoices")
    MCP_HEADERS.merge("Authorization" => "Bearer #{token}")
  end

  def initialize_request
    {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } }
    }
  end
end
