require "test_helper"

class TraceparentHeaderMiddlewareTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "response has no traceparent header when OTel is not active" do
    get rails_health_check_path
    assert_nil response.headers["traceparent"]
  end
end
