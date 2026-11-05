require "test_helper"

class PaymentIntentReconciliationJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @invoice = invoices(:sakura_january)
    attach_deliverables @invoice
  end

  test "a fetched short transfer emails the client what is still due" do
    Stripe::PaymentIntent.stubs(:retrieve).with("pi_short").returns(short_transfer)

    assert_enqueued_emails 1 do
      PaymentIntentReconciliationJob.perform_now "pi_short"
    end
    assert_equal 247_060, @invoice.reload.partial_payment_notified_amount
  end

  test "a rate limit is retried" do
    Stripe::PaymentIntent.stubs(:retrieve).raises(Stripe::RateLimitError.new("slow down"))

    assert_enqueued_with job: PaymentIntentReconciliationJob, args: [ "pi_busy" ] do
      PaymentIntentReconciliationJob.perform_now "pi_busy"
    end
  end

  test "a PaymentIntent Stripe does not know is discarded and reported" do
    Stripe::PaymentIntent.stubs(:retrieve).raises(Stripe::InvalidRequestError.new("No such payment_intent", "id"))

    report = assert_error_reported(Stripe::InvalidRequestError) do
      assert_no_enqueued_jobs only: PaymentIntentReconciliationJob do
        PaymentIntentReconciliationJob.perform_now "pi_missing"
      end
    end
    assert_equal "pi_missing", report.context[:payment_intent_id]
  end

  private

  def short_transfer
    Stripe::PaymentIntent.construct_from(id: "pi_short", status: "requires_action", amount: 247_500,
      metadata: { invoice_id: @invoice.id.to_s },
      next_action: { type: "display_bank_transfer_instructions", display_bank_transfer_instructions: {
        amount_remaining: 440, hosted_instructions_url: "https://payments.stripe.com/bank_transfers/instructions/test_example",
        financial_addresses: [ { type: "zengin", zengin: {
          bank_name: "Example Bank", branch_name: "Sample Branch", account_type: "futsu",
          account_number: "7654321", account_holder_name: "Example Consulting" } } ] } })
  end
end
