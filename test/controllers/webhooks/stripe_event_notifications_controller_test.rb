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

  test "signed delayed payment notifications enqueue reconciliation of their session" do
    %w[ v1.checkout.session.async_payment_succeeded v1.checkout.session.async_payment_failed ].each do |type|
      assert_enqueued_with job: CheckoutSessionReconciliationJob, args: [ "cs_thin_konbini" ] do
        post_notification type:, session_id: "cs_thin_konbini"
      end
      assert_response :accepted
    end
  end

  test "a signed partially funded notification enqueues reconciliation of its PaymentIntent" do
    assert_enqueued_with job: PaymentIntentReconciliationJob, args: [ "pi_thin_short" ] do
      post_notification type: "v1.payment_intent.partially_funded",
        related_object: { id: "pi_thin_short", type: "payment_intent", url: "/v1/payment_intents/pi_thin_short" }
    end
    assert_response :accepted
  end

  test "a cash balance transaction enqueues settlement for its client" do
    stub_cash_balance_transaction type: "funded"

    assert_enqueued_with job: CashBalanceSettlementJob, args: [ clients(:sakura) ] do
      post_cash_balance_notification
    end
    assert_response :accepted
  end

  test "a cash balance transaction for a customer this app does not know is ignored" do
    stub_cash_balance_transaction type: "funded", customer: "cus_someone_else"

    assert_no_enqueued_jobs { post_cash_balance_notification }
    assert_response :accepted
  end

  test "unclaimed credit Stripe moved to the account balance is reported" do
    stub_cash_balance_transaction type: "transferred_to_balance"

    assert_error_reported(Client::CashBalanceTransferredError) { post_cash_balance_notification }
  end

  test "a cancelled return releases the fee it charged before settling" do
    stub_cash_balance_transaction type: "return_canceled"
    Client.any_instance.expects(:release_return_fee!)

    assert_enqueued_with(job: CashBalanceSettlementJob) { post_cash_balance_notification }
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

  def stub_cash_balance_transaction(type:, customer: "cus_test_sakura123")
    Stripe::Events::V1CustomerCashBalanceTransactionCreatedEventNotification.any_instance.stubs(:fetch_related_object)
      .returns(Stripe::CustomerCashBalanceTransaction.construct_from(id: "ccsbtxn_test", customer:, type:, net_amount: 10_000))
  end

  def post_cash_balance_notification
    post_notification type: "v1.customer_cash_balance_transaction.created",
      related_object: { id: "ccsbtxn_test", type: "customer_cash_balance_transaction",
                        url: "/v1/customers/cus_test_sakura123/cash_balance_transactions/ccsbtxn_test" }
  end

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
