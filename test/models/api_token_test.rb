require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "validates required fields" do
    token = ApiToken.new
    assert_not token.valid?
    assert token.errors[:name].any?
  end

  test "generates token and digest on create" do
    token = users(:daniel).api_tokens.create!(name: "Test token")
    assert token.plain_token.present?
    assert token.token_digest.present?
    assert_equal Digest::SHA256.hexdigest(token.plain_token), token.token_digest
  end

  test "plain_token is only available after create" do
    token = api_tokens(:chrome_extension)
    assert_nil token.plain_token
  end

  test "find_by_token returns matching token" do
    found = ApiToken.find_by_token("test_token_abc123")
    assert_equal api_tokens(:chrome_extension), found
  end

  test "find_by_token returns nil for invalid token" do
    assert_nil ApiToken.find_by_token("wrong_token")
  end

  test "find_by_token returns nil for blank token" do
    assert_nil ApiToken.find_by_token(nil)
    assert_nil ApiToken.find_by_token("")
  end

  test "touch_last_used updates timestamp" do
    token = api_tokens(:chrome_extension)
    original = token.last_used_at
    freeze_time do
      token.touch_last_used
      assert_equal Time.current, token.reload.last_used_at
    end
  end

  test "each created token has a unique digest" do
    token1 = users(:daniel).api_tokens.create!(name: "First")
    token2 = users(:daniel).api_tokens.create!(name: "Second")
    assert_not_equal token1.token_digest, token2.token_digest
  end
end
