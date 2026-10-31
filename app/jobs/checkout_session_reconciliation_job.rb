class CheckoutSessionReconciliationJob < ApplicationJob
  queue_as :default

  # Stripe stopped retrying once the webhook returned 200, so this budget (about
  # four hours) is the only retry a payment gets before it needs the owner.
  retry_on Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError,
    wait: :polynomially_longer, attempts: 10 do |job, error|
    job.send :report, error
  end

  discard_on Stripe::AuthenticationError, Stripe::InvalidRequestError do |job, error|
    job.send :report, error
  end

  def perform(session_id)
    Invoice.apply_checkout_session Stripe::Checkout::Session.retrieve(session_id)
  end

  private

  def report(error)
    Rails.error.report error, context: { session_id: arguments.first }
  end
end
