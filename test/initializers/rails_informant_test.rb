require "test_helper"

class RailsInformantTest < ActiveSupport::TestCase
  test "a captured request URL leaves out the link token" do
    env = Rack::MockRequest.env_for("https://example.com/credit/abc%2D%2Ddef?locale=ja")

    url = RailsInformant::ContextBuilder.build_request_context(env)[:url]

    assert_equal "https://example.com/credit/[FILTERED]?locale=ja", url
  end

  test "a captured Referer leaves out the token of the page that posted the form" do
    env = Rack::MockRequest.env_for("https://example.com/pay/abc--def", method: "POST", "HTTP_REFERER" => "https://example.com/pay/abc--def")

    headers = RailsInformant::ContextBuilder.build_request_context(env)[:headers]

    assert_equal "https://example.com/pay/[FILTERED]", headers["Referer"]
  end

  test "an error raised under rails runner is not recorded" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant.stubs(:runner_mode?).returns(true)

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      RailsInformant::ErrorRecorder.record RuntimeError.new("runner failure")
    end
  end

  test "the same error outside rails runner is recorded" do
    RailsInformant.stubs(:initialized?).returns(true)

    assert_difference -> { RailsInformant::ErrorGroup.count } do
      RailsInformant::ErrorRecorder.record RuntimeError.new("server failure")
    end
  end

  test "breadcrumbs leave out the token in a request path and a redirect" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "process_action.action_controller", message: "process_action", metadata: { path: "/passwords/abc--def/edit" }
    buffer.record category: "redirect_to.action_controller", message: "redirect_to", metadata: { location: "https://checkout.stripe.com/c/pay/cs_test_a1b2" }

    paths = buffer.flush.map { it[:metadata].values_at(:path, :location).compact.sole }
    assert_equal [ "/passwords/[FILTERED]/edit", "https://checkout.stripe.com/c/pay/[FILTERED]" ], paths
  end
end
