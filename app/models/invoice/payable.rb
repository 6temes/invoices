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
  FAILED_PAYMENT_INTENT_STATUSES = %w[ requires_payment_method canceled ].freeze

  class_methods do
    def reconcile_checkout_session(session)
      apply_checkout_session session, payment_intent: unsettled_payment_intent(session)
    end

    # A completed session reads the same while a delayed payment is pending and
    # after it failed; only its PaymentIntent tells them apart.
    def unsettled_payment_intent(session)
      Stripe::PaymentIntent.retrieve(session.payment_intent) if session.status == "complete" && session.payment_status == "unpaid"
    end

    def apply_checkout_session(session, payment_intent: nil)
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

      invoice.apply_checkout_session session, payment_intent:
    end
  end

  def reconcile_checkout_session(session)
    apply_checkout_session session, payment_intent: self.class.unsettled_payment_intent(session)
  end

  def apply_checkout_session(session, payment_intent: nil)
    outcome = with_lock do
      if paid?
        report_unrecorded_payment session if session.payment_status == "paid" && session.id != stripe_checkout_session_id
        next :unchanged
      end

      case session.status
      when "expired"
        forget_checkout_session session
        :expired
      when "complete"
        apply_completed_checkout session, payment_intent
      else
        :unchanged
      end
    end

    send_receipt if outcome == :paid
    outcome
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

  def apply_completed_checkout(session, payment_intent)
    case session.payment_status
    when "paid"
      record_checkout_payment session
    when "unpaid"
      if payment_intent&.status.in? FAILED_PAYMENT_INTENT_STATUSES
        forget_checkout_session session
        :failed
      else
        :pending
      end
    else
      report_checkout_error session, UnpaidCheckoutError.new("Checkout session completed without payment")
    end
  end

  def record_checkout_payment(session)
    if session.currency != CURRENCY
      report_checkout_error session, CurrencyMismatchError.new("Checkout session currency mismatch")
    elsif session.amount_total != total
      report_checkout_error session, AmountMismatchError.new("Checkout session amount mismatch")
    else
      record_payment! stripe_checkout_session_id: session.id, stripe_payment_intent_id: session.payment_intent
      :paid
    end
  end

  def report_checkout_error(session, error)
    Rails.error.report error, context: { invoice_id: id, session_id: session.id, payment_status: session.payment_status,
      currency: session.currency, expected: total, actual: session.amount_total }, handled: true
    :unchanged
  end

  def forget_checkout_session(session)
    update! stripe_checkout_session_id: nil if sent? && session.id == stripe_checkout_session_id
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
