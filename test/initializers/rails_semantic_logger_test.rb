require "test_helper"

class RailsSemanticLoggerTest < ActionDispatch::IntegrationTest
  test "logs unpermitted parameters without the request" do
    user = User.take
    logger = SemanticLogger::Test::CaptureLogEvents.new
    ActionController::Base.stubs(:logger).returns(logger)

    put password_path(user.password_reset_token), params: { password: "new", password_confirmation: "new" }

    log = logger.events.find { it.message.start_with?("Unpermitted parameter") }
    assert_equal %w[token], log.payload[:keys]
    assert_equal "PasswordsController", log.payload[:context][:controller]
    assert_not log.payload[:context].key?(:request)
    assert_nothing_raised { log.payload.to_json }
  end
end
