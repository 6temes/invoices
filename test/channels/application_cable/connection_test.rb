require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with an active session" do
    cookies.signed[:session_id] = sessions(:daniel_session).id

    connect

    assert_equal users(:daniel), connection.current_user
  end

  test "rejects a session left idle past the limit" do
    session = sessions(:daniel_session)
    session.update_columns updated_at: (Session::IDLE_TIMEOUT + 1.minute).ago
    cookies.signed[:session_id] = session.id

    assert_reject_connection { connect }
  end
end
