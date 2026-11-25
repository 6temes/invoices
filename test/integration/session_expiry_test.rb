require "test_helper"

class SessionExpiryTest < ActionDispatch::IntegrationTest
  test "a session left idle past the limit has to sign in again" do
    sign_in_as users(:daniel)
    Current.session.update_columns updated_at: (Session::IDLE_TIMEOUT + 1.minute).ago

    get root_path

    assert_redirected_to new_session_path
  end

  test "a session in use stays signed in" do
    sign_in_as users(:daniel)
    Current.session.update_columns updated_at: 2.days.ago

    get root_path

    assert_response :success
  end
end
