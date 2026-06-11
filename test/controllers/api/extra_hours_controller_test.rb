require "test_helper"

class Api::ExtraHoursControllerTest < ActionDispatch::IntegrationTest
  test "create saves extra hour via API" do
    assert_difference "ExtraHour.count" do
      post api_extra_hours_path,
        params: {
          client_id: clients(:acme).id,
          hours: 1.5,
          description: "#42 — Fix login bug",
          performed_on: "2026-02-25",
          github_url: "https://github.com/acme/web-app/issues/42"
        },
        headers: { "Authorization" => "Bearer test_token_abc123" },
        as: :json
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert_equal "1.5", body["hours"]
    assert_equal "#42 — Fix login bug", body["description"]
  end

  test "create with invalid params returns errors" do
    post api_extra_hours_path,
      params: { client_id: clients(:acme).id, hours: 0 },
      headers: { "Authorization" => "Bearer test_token_abc123" },
      as: :json
    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert body["errors"].any?
  end

  test "returns unauthorized without token" do
    post api_extra_hours_path, params: { client_id: clients(:acme).id, hours: 1 }, as: :json
    assert_response :unauthorized
  end

  test "touches api token last_used_at" do
    token = api_tokens(:chrome_extension)
    old_used = token.last_used_at

    freeze_time do
      get api_clients_path, headers: { "Authorization" => "Bearer test_token_abc123" }
      assert_not_equal old_used, token.reload.last_used_at
    end
  end
end
