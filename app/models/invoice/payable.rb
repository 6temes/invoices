module Invoice::Payable
  extend ActiveSupport::Concern

  CheckoutError = Class.new(StandardError)
  AmountMismatchError = Class.new(CheckoutError)
  CurrencyMismatchError = Class.new(CheckoutError)
  InvoiceNotFoundError = Class.new(CheckoutError)
  MissingMetadataError = Class.new(CheckoutError)
  UnpaidCheckoutError = Class.new(CheckoutError)
  UnrecordedPaymentError = Class.new(CheckoutError)

  CURRENCY = "jpy"

  class_methods do
    def apply_checkout_session(session)
      invoice_id = session.metadata["invoice_id"]
      unless invoice_id
        Rails.error.report MissingMetadataError.new("Checkout session has no invoice_id in metadata"),
          context: { session_id: session.id }, handled: true
        return
      end

      invoice = find_by(id: invoice_id)
      unless invoice
        Rails.error.report InvoiceNotFoundError.new("Checkout session names an unknown invoice"),
          context: { invoice_id:, session_id: session.id }, handled: true
        return
      end

      invoice.apply_checkout_session session
    end
  end

  def apply_checkout_session(session)
    paid_now = with_lock do
      if paid?
        report_unrecorded_payment session if session.payment_status == "paid" && session.id != stripe_checkout_session_id
        next false
      end

      case session.status
      when "expired"
        update! stripe_checkout_session_id: nil if sent? && session.id == stripe_checkout_session_id
        false
      when "complete"
        record_checkout_payment session
      else
        false
      end
    end

    send_receipt if paid_now
  end

  def mark_as_paid!(**)
    with_lock { record_payment!(**) }
    send_receipt
  end

  def create_checkout_session!
    raise Invoice::InvalidStatusError, "Cannot create checkout session for paid invoice" if paid?

    token = signed_id purpose: :payment, expires_in: 60.days
    host = default_host

    session = Stripe::Checkout::Session.create(
      customer: client.stripe_customer.id,
      line_items: [ {
        price_data: {
          currency: CURRENCY,
          product_data: { name: "Invoice ##{invoice_number} — #{subject}" },
          unit_amount: total
        },
        quantity: 1
      } ],
      mode: "payment",
      payment_method_types: [ "card" ],
      success_url: Rails.application.routes.url_helpers.public_payment_url(token:, host:),
      cancel_url: Rails.application.routes.url_helpers.public_payment_url(token:, host:),
      metadata: { invoice_id: id }
    )

    with_lock do
      raise Invoice::InvalidStatusError, "Cannot create checkout session for paid invoice" if paid?
      update! stripe_checkout_session_id: session.id
    end
    session
  end

  private

  def record_checkout_payment(session)
    context = { invoice_id: id, session_id: session.id }

    error =
      if session.payment_status != "paid"
        UnpaidCheckoutError.new("Checkout session completed without payment")
      elsif session.currency != CURRENCY
        CurrencyMismatchError.new("Checkout session currency mismatch")
      elsif session.amount_total != total
        AmountMismatchError.new("Checkout session amount mismatch")
      end

    if error
      Rails.error.report error, context: context.merge(payment_status: session.payment_status,
        currency: session.currency, expected: total, actual: session.amount_total), handled: true
      return false
    end

    record_payment! stripe_checkout_session_id: session.id, stripe_payment_intent_id: session.payment_intent
    true
  end

  def record_payment!(paid_on: Date.current, stripe_checkout_session_id: nil, stripe_payment_intent_id: nil)
    raise Invoice::InvalidStatusError, "Invoice must be sent to mark as paid" unless sent?

    update! status: :paid, paid_on:, paid_amount: total, stripe_checkout_session_id:, stripe_payment_intent_id:
  end

  def report_unrecorded_payment(session)
    Rails.error.report UnrecordedPaymentError.new("Paid checkout session for an invoice already paid another way"),
      context: { invoice_id: id, session_id: session.id, payment_intent_id: session.payment_intent }, handled: true
  end

  # The lock's transaction has committed by now, and enqueue_after_transaction_commit
  # is off, so enqueueing inside it would send a receipt for a rolled-back payment.
  def send_receipt
    InvoiceMailer.send_receipt(self).deliver_later
  end
end
