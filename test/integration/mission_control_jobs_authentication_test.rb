require "test_helper"

class MissionControlJobsAuthenticationTest < ActionDispatch::IntegrationTest
  # Regression: Mission Control's ApplicationController overrides default_url_options
  # with { server_id: MissionControl::Jobs::Current.server }. For an unauthenticated
  # request the server context is nil, so the host's redirect to new_session_path was
  # generated as new_session_path(server_id: nil), raising ActionController::UrlGenerationError.
  test "unauthenticated request to /jobs redirects to login" do
    get "/jobs"

    assert_response :redirect
    assert_equal "/session/new", URI(response.location).path
  end
end
