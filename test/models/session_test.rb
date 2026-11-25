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

  test "resume finds a session used within the idle limit and records the activity" do
    session = sessions(:daniel_session)
    session.update_columns updated_at: 2.days.ago

    assert_equal session, Session.resume(session.id)
    assert_in_delta Time.current, session.reload.updated_at, 1.second
  end

  test "resume ignores a session left idle past the limit" do
    session = sessions(:daniel_session)
    session.update_columns updated_at: (Session::IDLE_TIMEOUT + 1.minute).ago

    assert_nil Session.resume(session.id)
  end

  test "resume ignores a session older than the lifetime even when recently used" do
    session = sessions(:daniel_session)
    session.update_columns created_at: (Session::LIFETIME + 1.minute).ago, updated_at: 1.minute.ago

    assert_nil Session.resume(session.id)
  end

  test "resume does not write while the session was used within the last hour" do
    session = sessions(:daniel_session)
    session.update_columns updated_at: 10.minutes.ago

    assert_no_changes -> { session.reload.updated_at } do
      Session.resume session.id
    end
  end

  test "delete_expired removes idle and over-age sessions only" do
    user = users(:daniel)
    active = sessions(:daniel_session)
    idle = user.sessions.create!.tap { it.update_columns updated_at: (Session::IDLE_TIMEOUT + 1.minute).ago }
    over_age = user.sessions.create!.tap { it.update_columns created_at: (Session::LIFETIME + 1.minute).ago }

    Session.delete_expired

    assert Session.exists?(active.id)
    assert_not Session.exists?(idle.id)
    assert_not Session.exists?(over_age.id)
  end
end
