class WebhooksController < ApplicationController
  WebhookError = Class.new(StandardError)
  AmountMismatchError = Class.new(WebhookError)
  CurrencyMismatchError = Class.new(WebhookError)
  InvoiceNotFoundError = Class.new(WebhookError)
  MissingMetadataError = Class.new(WebhookError)

  allow_unauthenticated_access
  skip_forgery_protection

  def stripe
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, sig_header, Rails.application.credentials.dig(:stripe, :webhook_secret)
    )

    case event.type
    when "checkout.session.completed"
      handle_checkout_completed event.data.object
    when "checkout.session.expired"
      handle_checkout_expired event.data.object
    end

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end

  private

  def handle_checkout_completed(session)
    invoice_id = session.metadata["invoice_id"]
    unless invoice_id
      Rails.error.report MissingMetadataError.new("Stripe webhook missing invoice_id in metadata"),
        context: { session_id: session.id }, handled: true
      return
    end

    invoice = Invoice.find_by(id: invoice_id)
    unless invoice
      Rails.error.report InvoiceNotFoundError.new("Stripe webhook invoice not found"),
        context: { invoice_id: }, handled: true
      return
    end

    if invoice.paid?
      Rails.logger.info "[Stripe Webhook] Invoice #{invoice_id} already paid, skipping"
      return
    end

    unless session.currency == "jpy"
      Rails.error.report CurrencyMismatchError.new("Stripe webhook currency mismatch"),
        context: { invoice_id:, currency: session.currency }, handled: true
      return
    end

    unless session.amount_total == invoice.total
      Rails.error.report AmountMismatchError.new("Stripe webhook amount mismatch"),
        context: { invoice_id:, expected: invoice.total, actual: session.amount_total }, handled: true
      return
    end

    invoice.mark_as_paid!(
      stripe_checkout_session_id: session.id,
      stripe_payment_intent_id: session.payment_intent
    )
  end

  def handle_checkout_expired(session)
    invoice_id = session.metadata["invoice_id"]
    return unless invoice_id

    Invoice.where(id: invoice_id, status: :sent, stripe_checkout_session_id: session.id)
           .update_all stripe_checkout_session_id: nil
  end
end
