module Invoice::Payable
  extend ActiveSupport::Concern

  CheckoutError = Class.new(StandardError)
  CurrencyMismatchError = Class.new(CheckoutError)
  InvoiceNotFoundError = Class.new(CheckoutError)
  MissingMetadataError = Class.new(CheckoutError)
  UnpaidCheckoutError = Class.new(CheckoutError)

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

  def checkout_pending?
    return false if stripe_checkout_session_id.blank?

    session = Stripe::Checkout::Session.retrieve stripe_checkout_session_id
    session.status == "complete" && reconcile_checkout_session(session) == :pending
  end

  def apply_checkout_session(session, payment_intent: nil)
    stored_session_id = nil
    outcome = with_lock do
      stored_session_id = stripe_checkout_session_id

      case
      when session.status == "complete" && session.payment_status == "paid"
        record_checkout_payment session
      when paid?
        :unchanged
      when session.status == "expired"
        forget_checkout_session session
        :expired
      when session.status == "complete"
        apply_completed_checkout session, payment_intent
      else
        :unchanged
      end
    end

    settle_payment outcome, pending_session_id: (stored_session_id unless stored_session_id == session.id)
    outcome
  end

  def mark_as_paid!(paid_on: Date.current)
    stored_session_id = nil
    outcome = with_lock do
      raise Invoice::InvalidStatusError, "Invoice must be sent to mark as paid" unless sent?

      stored_session_id = stripe_checkout_session_id
      record_payment!(kind: :manual, amount: amount_due, paid_on:)
    end

    settle_payment outcome, pending_session_id: stored_session_id
  end

  def create_checkout_session!
    raise Invoice::InvalidStatusError, "Cannot create checkout session with nothing due" unless amount_due.positive?

    token = signed_id purpose: :payment, expires_in: 60.days
    host = default_host

    session = Stripe::Checkout::Session.create(
      customer: client.stripe_customer.id,
      line_items: [ {
        price_data: {
          currency: CURRENCY,
          product_data: { name: "Invoice ##{invoice_number} — #{subject}" },
          unit_amount: amount_due
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
    when "unpaid"
      if payment_intent&.status.in? FAILED_PAYMENT_INTENT_STATUSES
        forget_checkout_session session
        :failed
      else
        adopt_checkout_session session
        :pending
      end
    else
      report_checkout_error session, UnpaidCheckoutError.new("Checkout session completed without payment")
    end
  end

  def record_checkout_payment(session)
    if session.currency != CURRENCY
      report_checkout_error session, CurrencyMismatchError.new("Checkout session currency mismatch")
    else
      record_payment! kind: :checkout, amount: session.amount_total, stripe_payment_intent_id: session.payment_intent,
        stripe_checkout_session_id: session.id
    end
  end

  def report_checkout_error(session, error)
    Rails.error.report error, context: { invoice_id: id, session_id: session.id, payment_status: session.payment_status,
      currency: session.currency, expected: total, actual: session.amount_total }, handled: true
    :unchanged
  end

  # Two tabs can each start a session; the one with a payment under way must be
  # the stored one, or the next Pay click would start a second payment.
  def adopt_checkout_session(session)
    update! stripe_checkout_session_id: session.id if sent? && session.id != stripe_checkout_session_id
  end

  def forget_checkout_session(session)
    update! stripe_checkout_session_id: nil if sent? && session.id == stripe_checkout_session_id
  end

  # Money that has arrived is recorded whatever the invoice still owed; only what
  # it owed is kept, and the rest waits on the row to be refunded.
  def record_payment!(kind:, amount:, paid_on: Date.current, stripe_payment_intent_id: nil, stripe_checkout_session_id: nil)
    raise Invoice::InvalidStatusError, "Invoice must be sent to record a payment" unless sent? || paid?
    return :unchanged if stripe_payment_intent_id && payments.exists?(stripe_payment_intent_id:)

    kept = [ amount, amount_due ].min
    payments.create!(kind:, amount: kept, excess_amount: amount - kept, stripe_payment_intent_id:)
    # A cache of the ledger, so it is written in the same transaction.
    self.paid_amount = payments.succeeded.sum(:amount)

    if sent? && amount_due.zero?
      update!(status: :paid, paid_on:, stripe_checkout_session_id:)
      :paid
    else
      save!
      :recorded
    end
  end

  # The lock's transaction has committed by now, and enqueue_after_transaction_commit
  # is off, so enqueueing inside it would send a receipt for a rolled-back payment.
  # Refunds go last: a failed one is retried from its row, which repeats nothing else.
  def settle_payment(outcome, pending_session_id:)
    if outcome == :paid
      send_receipt
      release_pending_checkout pending_session_id if pending_session_id
    end
    refund_excess!
  end

  def send_receipt
    InvoiceMailer.send_receipt(self).deliver_later
  end

  # Another route paid, so the session the invoice was waiting on must not take the
  # client's money too; cancelling a transfer returns its funds to their balance.
  def release_pending_checkout(session_id)
    session = Stripe::Checkout::Session.retrieve session_id
    case session.status
    when "open"
      Stripe::Checkout::Session.expire session.id
    when "complete"
      intent = Stripe::PaymentIntent.retrieve session.payment_intent
      Stripe::PaymentIntent.cancel intent.id if intent.status == "requires_action"
    end
  rescue Stripe::StripeError => e
    Rails.error.report e, context: { invoice_id: id, session_id: }
  end

  # The API can only refund a cash balance payment to the client's bank, and Stripe
  # emails them for its details.
  def refund_excess!
    payments.where(excess_amount: 1.., stripe_refund_id: nil).find_each do |payment|
      intent = Stripe::PaymentIntent.retrieve id: payment.stripe_payment_intent_id, expand: [ "payment_method" ]
      params = { payment_intent: intent.id, amount: payment.excess_amount }
      params[:instructions_email] = client.email if intent.payment_method.type == "customer_balance"

      refund = Stripe::Refund.create params, { idempotency_key: "excess-#{payment.id}" }
      payment.update! stripe_refund_id: refund.id
    end
  end
end
