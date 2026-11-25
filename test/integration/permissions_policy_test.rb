require "test_helper"

class PermissionsPolicyTest < ActionDispatch::IntegrationTest
  test "responses deny unused browser features in both policy headers" do
    get new_session_path

    assert_includes response.headers["Permissions-Policy"].split(", "), "camera=()"
    assert_includes response.headers["Permissions-Policy"].split(", "), "picture-in-picture=()"
    assert_includes response.headers["Feature-Policy"], "camera 'none'"
  end
end
