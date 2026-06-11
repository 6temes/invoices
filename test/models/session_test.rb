require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "belongs to user" do
    session = sessions(:daniel_session)
    assert_equal users(:daniel), session.user
  end

  test "is destroyed when user is destroyed" do
    user = users(:daniel)
    session_id = sessions(:daniel_session).id

    user.destroy
    assert_not Session.exists?(session_id)
  end
end
