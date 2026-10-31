require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  MCP_HEADERS = {
    "Accept" => "application/json, text/event-stream",
    "MCP-Protocol-Version" => "2025-06-18"
  }

  test "refuses a request without a token" do
    post mcp_path, params: initialize_request, headers: MCP_HEADERS, as: :json
    assert_response :unauthorized
    assert_equal "Bearer", response.headers["WWW-Authenticate"]
  end

  test "refuses an unknown token as invalid" do
    post mcp_path, params: initialize_request, headers: auth("wrong_token"), as: :json
    assert_response :unauthorized
    assert_equal 'Bearer error="invalid_token"', response.headers["WWW-Authenticate"]
  end

  test "refuses a Chrome extension token" do
    post mcp_path, params: initialize_request, headers: auth("test_token_abc123"), as: :json
    assert_response :forbidden
    assert_nil response.headers["WWW-Authenticate"]
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
      assert_equal Time.current, api_tokens(:agent).reload.last_used_at
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

  test "lists tools, with only mark_invoice_paid able to write" do
    post mcp_path, params: { jsonrpc: "2.0", id: 2, method: "tools/list" }, headers: auth, as: :json

    tools = response.parsed_body.dig("result", "tools").index_by { it["name"] }
    assert_equal %w[ get_invoice list_clients list_invoices mark_invoice_paid ], tools.keys.sort
    assert_equal %w[ mark_invoice_paid ], tools.reject { _2.dig("annotations", "readOnlyHint") }.keys
    assert tools.values.none? { it.dig("annotations", "destructiveHint") }
  end

  test "marks an invoice paid and records the token's owner as the author" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    post mcp_path, params: call_tool("mark_invoice_paid", invoice_number: invoice.invoice_number, paid_on: invoice.issue_date.iso8601), headers: auth, as: :json

    assert invoice.reload.paid?
    assert_equal users(:daniel).id.to_s, invoice.versions.last.whodunnit
  end

  test "rejects listing drafts" do
    post mcp_path, params: call_tool("list_invoices", year: 2026, status: "draft"), headers: auth, as: :json

    assert response.parsed_body.dig("result", "isError")
    assert_no_match(/invoice_number/, response.parsed_body.dig("result", "content", 0, "text"))
  end

  test "lists invoices through the endpoint" do
    post mcp_path, params: call_tool("list_invoices", year: 2026), headers: auth, as: :json

    text = response.parsed_body.dig("result", "content", 0, "text")
    assert_equal [ 145, 146 ], JSON.parse(text)["invoices"].pluck("invoice_number")
  end

  test "sends files in the MCP wire shape" do
    invoice = invoices(:sakura_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "invoice_146.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "invoice_146.xml", content_type: "application/xml"

    post mcp_path, params: call_tool("get_invoice", invoice_number: 146), headers: auth, as: :json

    assert_includes response.body, '"blob"'
    assert_includes response.body, '"mimeType"'
    assert_not_includes response.body, '"mime_type"'
    assert_not_includes response.body, '"data"'
  end

  private

  def call_tool(name, **arguments)
    { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name:, arguments: } }
  end

  def auth(token = "test_token_agent")
    MCP_HEADERS.merge("Authorization" => "Bearer #{token}")
  end

  def initialize_request
    {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } }
    }
  end
end
