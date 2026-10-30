require "test_helper"

class ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "create generates a new API token" do
    assert_difference "ApiToken.count" do
      post business_api_tokens_path, params: { api_token: { name: "New token" } }
    end
    assert_redirected_to edit_business_path
    assert flash[:token].present?, "Expected flash[:token] to contain the plain token"
  end

  test "create stores the chosen purpose" do
    post business_api_tokens_path, params: { api_token: { name: "Claude", purpose: "read_invoices" } }
    assert ApiToken.last.read_invoices?
  end

  test "settings page lists each token's purpose" do
    get edit_business_path
    assert_select "td", text: "Chrome extension"
    assert_select "td", text: "Read invoices"
  end

  test "create shows the plain token in a dialog" do
    post business_api_tokens_path, params: { api_token: { name: "New token" } }
    plain_token = flash[:token]
    follow_redirect!

    assert_select "dialog code", text: plain_token
  end

  test "destroy revokes a token" do
    token = api_tokens(:chrome_extension)
    assert_difference "ApiToken.count", -1 do
      delete business_api_token_path(token)
    end
    assert_redirected_to edit_business_path
  end
end
