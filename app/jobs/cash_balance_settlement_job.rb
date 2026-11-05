class CashBalanceSettlementJob < ApplicationJob
  queue_as :default

  limits_concurrency key: ->(client) { client }, duration: 10.minutes

  retry_on Stripe::APIConnectionError, Stripe::APIError, Stripe::RateLimitError,
    wait: :polynomially_longer, attempts: 10 do |job, error|
    job.send :report, error
  end

  discard_on Stripe::AuthenticationError, Stripe::InvalidRequestError do |job, error|
    job.send :report, error
  end

  def perform(client)
    client.settle_cash_balance!
  end

  private

  def report(error)
    Rails.error.report error, context: { client_id: arguments.first.id }
  end
end
