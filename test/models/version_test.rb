require "test_helper"

class VersionTest < ActiveSupport::TestCase
  test "actor returns the correct user from whodunnit" do
    user = users(:daniel)
    version = PaperTrail::Version.new whodunnit: user.id.to_s

    assert_equal user, version.actor
  end

  test "actor returns nil when whodunnit is blank" do
    version = PaperTrail::Version.new whodunnit: nil
    assert_nil version.actor
  end

  test "actor is memoized" do
    user = users(:daniel)
    version = PaperTrail::Version.new whodunnit: user.id.to_s

    assert_same version.actor, version.actor
  end
end
