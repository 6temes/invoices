class InvoiceDeliveryJob < ApplicationJob
  queue_as :default

  discard_on CloudflarePdfGateway::ClientError do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  discard_on Invoice::InvalidStatusError

  discard_on UblInvoiceBuilder::Error do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  discard_on Stripe::AuthenticationError do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  discard_on Stripe::InvalidRequestError do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on CloudflarePdfGateway::ServerError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on Stripe::APIError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  retry_on Stripe::RateLimitError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send :mark_invoice_failed, job.arguments.first, error
  end

  def perform(invoice)
    invoice.deliver!
  end

  private

  def mark_invoice_failed(invoice, error)
    Rails.error.report error, context: { invoice_id: invoice.id }
    invoice.mark_as_failed!
  end
end
