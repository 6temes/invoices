require "test_helper"

class Api::ClientsControllerTest < ActionDispatch::IntegrationTest
  test "index returns clients with github repos" do
    get api_clients_path, headers: { "Authorization" => "Bearer test_token_abc123" }
    assert_response :success

    body = JSON.parse(response.body)
    assert body.is_a?(Array)
    assert body.any? { it["name"] == "Acme Corp." }
    acme = body.find { it["name"] == "Acme Corp." }
    assert_equal [ "acme/web-app", "acme/api" ], acme["github_repos"]
  end

  test "returns unauthorized without token" do
    get api_clients_path
    assert_response :unauthorized
  end

  test "returns unauthorized with invalid token" do
    get api_clients_path, headers: { "Authorization" => "Bearer wrong_token" }
    assert_response :unauthorized
  end
end
