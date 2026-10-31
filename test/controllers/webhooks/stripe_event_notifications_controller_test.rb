require "test_helper"

class Webhooks::StripeEventNotificationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "a signed completed notification enqueues reconciliation of its session" do
    assert_enqueued_with job: CheckoutSessionReconciliationJob, args: [ "cs_thin_completed" ] do
      post_notification type: "v1.checkout.session.completed", session_id: "cs_thin_completed"
    end
    assert_response :accepted
  end

  test "a signed expired notification enqueues reconciliation of its session" do
    assert_enqueued_with job: CheckoutSessionReconciliationJob, args: [ "cs_thin_expired" ] do
      post_notification type: "v1.checkout.session.expired", session_id: "cs_thin_expired"
    end
    assert_response :accepted
  end

  test "a notification signed with another secret is rejected" do
    assert_no_enqueued_jobs do
      post_notification type: "v1.checkout.session.completed", secret: "whsec_someone_else"
    end
    assert_response :bad_request
  end

  test "a signed body that is not JSON is rejected" do
    payload = "not json"
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, Rails.configuration.x.stripe.thin_webhook_secret)

    post webhooks_stripe_event_notifications_path, params: payload,
      headers: { "Content-Type" => "application/json",
                 "Stripe-Signature" => Stripe::Webhook::Signature.generate_header(timestamp, signature) }

    assert_response :bad_request
  end

  test "an event type the app does not handle is acknowledged and reported" do
    assert_error_reported(StripeEventNotification::UnhandledEventError) do
      assert_no_enqueued_jobs do
        post_notification type: "v1.customer.created", related_object: { id: "cus_test", type: "customer", url: "/v1/customers/cus_test" }
      end
    end
    assert_response :accepted
  end

  test "a destination ping is acknowledged silently" do
    assert_no_error_reported do
      assert_no_enqueued_jobs do
        post_notification type: "v2.core.event_destination.ping", related_object: nil
      end
    end
    assert_response :accepted
  end

  private

  def post_notification(type:, session_id: "cs_test", secret: Rails.configuration.x.stripe.thin_webhook_secret,
                        related_object: { id: session_id, type: "checkout.session", url: "/v1/checkout/sessions/#{session_id}" })
    payload = { id: "evt_test_thin", object: "v2.core.event", type:, created: Time.current.iso8601, livemode: false,
                related_object: }.compact.to_json
    timestamp = Time.current
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)

    post webhooks_stripe_event_notifications_path, params: payload,
      headers: { "Content-Type" => "application/json",
                 "Stripe-Signature" => Stripe::Webhook::Signature.generate_header(timestamp, signature) }
  end
end
