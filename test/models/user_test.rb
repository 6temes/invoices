require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "requires a password of at least 12 characters" do
    user = users(:daniel)

    user.password = "x" * 11
    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)

    user.password = "x" * 12
    assert user.valid?
  end

  test "keeps an existing password valid when other attributes change" do
    user = users(:daniel)
    user.email_address = "owner@example.com"

    assert user.valid?
  end
end
