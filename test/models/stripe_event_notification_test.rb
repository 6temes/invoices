require "test_helper"

class StripeEventNotificationTest < ActiveSupport::TestCase
  test "refuses to handle notifications without a signing secret" do
    secret = Rails.configuration.x.stripe.thin_webhook_secret
    Rails.configuration.x.stripe.thin_webhook_secret = nil

    assert_raises(ArgumentError) { StripeEventNotification.receive "{}", "t=1,v1=abc" }
  ensure
    Rails.configuration.x.stripe.thin_webhook_secret = secret
  end
end
