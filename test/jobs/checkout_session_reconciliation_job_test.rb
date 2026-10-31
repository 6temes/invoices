require "test_helper"

class CheckoutSessionReconciliationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @invoice = invoices(:sakura_january)
    attach_deliverables @invoice
  end

  test "a fetched paid session marks the invoice paid and sends one receipt" do
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_paid").returns(session(id: "cs_paid", status: "complete", payment_status: "paid"))
    Stripe::PaymentIntent.expects(:retrieve).never

    assert_enqueued_emails 1 do
      CheckoutSessionReconciliationJob.perform_now "cs_paid"
    end
    assert @invoice.reload.paid?
  end

  test "a fetched session awaiting a delayed payment leaves the invoice sent" do
    @invoice.update_columns stripe_checkout_session_id: "cs_konbini"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_konbini").returns(session(id: "cs_konbini", status: "complete", payment_status: "unpaid"))
    Stripe::PaymentIntent.stubs(:retrieve).with("pi_test").returns(Stripe::PaymentIntent.construct_from(id: "pi_test", status: "requires_action"))

    assert_no_enqueued_emails do
      CheckoutSessionReconciliationJob.perform_now "cs_konbini"
    end
    assert @invoice.reload.sent?
    assert_equal "cs_konbini", @invoice.stripe_checkout_session_id
  end

  test "a fetched session whose delayed payment failed clears the matching stored id" do
    @invoice.update_columns stripe_checkout_session_id: "cs_konbini"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_konbini").returns(session(id: "cs_konbini", status: "complete", payment_status: "unpaid"))
    Stripe::PaymentIntent.stubs(:retrieve).with("pi_test").returns(Stripe::PaymentIntent.construct_from(id: "pi_test", status: "requires_payment_method"))

    assert_no_enqueued_emails do
      CheckoutSessionReconciliationJob.perform_now "cs_konbini"
    end
    assert @invoice.reload.sent?
    assert_nil @invoice.stripe_checkout_session_id
  end

  test "a fetched expired session clears the matching stored id" do
    @invoice.update_columns stripe_checkout_session_id: "cs_expired"
    Stripe::Checkout::Session.stubs(:retrieve).returns(session(id: "cs_expired", status: "expired", payment_status: "unpaid"))

    CheckoutSessionReconciliationJob.perform_now "cs_expired"

    assert_nil @invoice.reload.stripe_checkout_session_id
  end

  test "a rate limit is retried" do
    Stripe::Checkout::Session.stubs(:retrieve).raises(Stripe::RateLimitError.new("slow down"))

    assert_enqueued_with job: CheckoutSessionReconciliationJob, args: [ "cs_busy" ] do
      CheckoutSessionReconciliationJob.perform_now "cs_busy"
    end
    assert @invoice.reload.sent?
  end

  test "a connection error on every attempt is reported with the session id once retries run out" do
    Stripe::Checkout::Session.stubs(:retrieve).raises(Stripe::APIConnectionError.new("unreachable"))

    report = assert_error_reported(Stripe::APIConnectionError) do
      perform_enqueued_jobs { CheckoutSessionReconciliationJob.perform_later "cs_down" }
    end

    assert_equal "cs_down", report.context[:session_id]
    assert_performed_jobs 10
  end

  test "a session Stripe does not know is discarded and reported" do
    Stripe::Checkout::Session.stubs(:retrieve).raises(Stripe::InvalidRequestError.new("No such checkout.session", "id"))

    report = assert_error_reported(Stripe::InvalidRequestError) do
      assert_no_enqueued_jobs only: CheckoutSessionReconciliationJob do
        CheckoutSessionReconciliationJob.perform_now "cs_missing"
      end
    end
    assert_equal "cs_missing", report.context[:session_id]
  end

  test "a rejected API key is discarded and reported" do
    Stripe::Checkout::Session.stubs(:retrieve).raises(Stripe::AuthenticationError.new("Invalid API Key"))

    report = assert_error_reported(Stripe::AuthenticationError) do
      assert_no_enqueued_jobs only: CheckoutSessionReconciliationJob do
        CheckoutSessionReconciliationJob.perform_now "cs_unauthorized"
      end
    end
    assert_equal "cs_unauthorized", report.context[:session_id]
  end

  test "a paid session for a draft invoice fails the job" do
    draft = invoices(:acme_february_draft)
    Stripe::Checkout::Session.stubs(:retrieve).returns(session(id: "cs_draft", status: "complete", payment_status: "paid", invoice: draft))

    assert_raises Invoice::InvalidStatusError do
      CheckoutSessionReconciliationJob.perform_now "cs_draft"
    end
  end

  private

  def session(id:, status:, payment_status:, invoice: @invoice)
    Stripe::Checkout::Session.construct_from(
      id:, status:, payment_status:, currency: "jpy", amount_total: invoice.total, payment_intent: "pi_test",
      metadata: { invoice_id: invoice.id.to_s }
    )
  end
end
