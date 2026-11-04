class PaymentIntentReconciliationJob < ApplicationJob
  queue_as :default

  retry_on Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError,
    wait: :polynomially_longer, attempts: 10 do |job, error|
    job.send :report, error
  end

  discard_on Stripe::AuthenticationError, Stripe::InvalidRequestError do |job, error|
    job.send :report, error
  end

  def perform(payment_intent_id)
    Invoice.notice_partial_payment Stripe::PaymentIntent.retrieve(payment_intent_id)
  end

  private

  def report(error)
    Rails.error.report error, context: { payment_intent_id: arguments.first }
  end
end
