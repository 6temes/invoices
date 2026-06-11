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

  test "destroy revokes a token" do
    token = api_tokens(:chrome_extension)
    assert_difference "ApiToken.count", -1 do
      delete business_api_token_path(token)
    end
    assert_redirected_to edit_business_path
  end
end
