module Invoice::Payable
  extend ActiveSupport::Concern

  CheckoutError = Class.new(StandardError)
  CurrencyMismatchError = Class.new(CheckoutError)
  InvoiceNotFoundError = Class.new(CheckoutError)
  MissingMetadataError = Class.new(CheckoutError)
  UnrecordedPaymentError = Class.new(CheckoutError)
  UnpaidCheckoutError = Class.new(CheckoutError)

  CURRENCY = "jpy"
  # Stripe's smallest JPY charge, for a credit PaymentIntent and for Checkout alike.
  MINIMUM_CHARGE = 50
  # How long Stripe honours an idempotency key.
  IDEMPOTENCY_WINDOW = 24.hours
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

    def notice_partial_payment(intent)
      return unless intent.status == "requires_action"

      invoice_id = intent.metadata["invoice_id"] || checkout_session_invoice_id(intent)
      find_by(id: invoice_id)&.notice_partial_payment Invoice::PendingPayment.from(intent)
    end

    def checkout_session_invoice_id(intent)
      Stripe::Checkout::Session.list(payment_intent: intent.id).data.first&.metadata&.[]("invoice_id")
    end
    private :checkout_session_invoice_id
  end

  def reconcile_checkout_session(session)
    apply_checkout_session session, payment_intent: self.class.unsettled_payment_intent(session)
  end

  def pending_payment
    return if stripe_checkout_session_id.blank?

    session = Stripe::Checkout::Session.retrieve stripe_checkout_session_id
    return unless session.status == "complete"

    intent = self.class.unsettled_payment_intent(session)
    Invoice::PendingPayment.from(intent) if apply_checkout_session(session, payment_intent: intent) == :pending
  end

  # Stripe redelivers events and sends them out of order, so only a larger amount
  # than the client was last told about is news.
  def notice_partial_payment(pending)
    noticed = with_lock do
      if sent? && pending.amount_received > partial_payment_notified_amount
        update! partial_payment_notified_amount: pending.amount_received
      end
    end

    InvoiceMailer.send_partial_payment(self, pending.to_h).deliver_later if noticed
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
    return if apply_paid_stored_checkout == :paid

    stored_session_id = nil
    outcome = with_lock do
      raise Invoice::InvalidStatusError, "Invoice must be sent to mark as paid" unless sent?

      stored_session_id = stripe_checkout_session_id
      record_payment!(kind: :manual, amount: amount_due, paid_on:)
    end

    settle_payment outcome, pending_session_id: stored_session_id
  end

  # The payment that settled the invoice carries the same date, so a correction moves both.
  def correct_paid_on(paid_on)
    with_lock do
      update(paid_on:).tap do |updated|
        payments.succeeded.where(amount: 1..).order(:id).last.update!(paid_on: self.paid_on) if updated
      end
    end
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
      metadata: { invoice_id: id },
      payment_intent_data: { metadata: { invoice_id: id } }
    )

    with_lock do
      raise Invoice::InvalidStatusError, "Cannot create checkout session for paid invoice" if paid?
      update! stripe_checkout_session_id: session.id
    end
    session
  end

  def latest_paid_on
    [ Date.current, issue_date ].compact.max
  end

  def credit_applied
    payments.credit.succeeded.sum(:amount)
  end

  def apply_credit!
    draw_credit unless payments.credit.succeeded.exists?
    trim_kept_credit if payments.credit.succeeded.exists?
  end

  private

  # The row is written before Stripe is asked, so a crash replays the same
  # amount and key and Stripe answers with the same PaymentIntent.
  def draw_credit
    2.times do
      payment = payments.credit.pending.first || start_credit(client.cash_balance)
      return unless payment

      intent = payment.created_at.after?(IDEMPOTENCY_WINDOW.ago) ? confirm_credit(payment) : find_credit_intent(payment)
      return keep_credit(payment, intent) if intent&.status == "succeeded"

      # A balance spent since it was read leaves the intent waiting for a transfer;
      # cancelling it returns what it took, and the next pass draws what is left.
      Stripe::PaymentIntent.cancel intent.id if intent&.status == "requires_action"
      payment.destroy!
    end
  end

  def start_credit(balance)
    amount = credit_for(balance)
    return if amount.zero?

    with_lock do
      payments.create!(kind: :credit, status: :pending, amount:).tap do
        it.update! idempotency_key: "invoice-payment-#{it.id}"
      end
    end
  end

  # A cache of the ledger, so it is written in the same transaction.
  def refresh_paid_amount
    self.paid_amount = payments.succeeded.sum(:amount)
  end

  # Never leaves less than the minimum charge due, so Checkout can still collect
  # the rest, and never draws less than it, which Stripe would refuse.
  def credit_for(balance)
    credit = balance >= amount_due ? amount_due : [ balance, amount_due - MINIMUM_CHARGE ].min
    credit < MINIMUM_CHARGE ? 0 : credit
  end

  def confirm_credit(payment)
    Stripe::PaymentIntent.create({
      amount: payment.amount,
      currency: CURRENCY,
      customer: client.stripe_customer_id,
      automatic_payment_methods: { enabled: true, allow_redirects: "never" },
      payment_method_data: { type: "customer_balance" },
      confirm: true,
      metadata: { invoice_id: id, invoice_payment_id: payment.id }
    }, { idempotency_key: payment.idempotency_key })
  end

  def find_credit_intent(payment)
    Stripe::PaymentIntent.list(customer: client.stripe_customer_id, created: { gte: payment.created_at.to_i }, limit: 100)
      .auto_paging_each.find { it.metadata["invoice_payment_id"] == payment.id.to_s }
  end

  def keep_credit(payment, intent)
    with_lock do
      payment.update! status: :succeeded, stripe_payment_intent_id: intent.id
      refresh_paid_amount
      save!
    end
  end

  # A total edited since the credit was drawn: the credit gives back what the
  # total no longer needs, or enough to leave the minimum charge due.
  def trim_kept_credit
    with_lock do
      excess = case amount_due
      when ...0 then -amount_due
      when 1...MINIMUM_CHARGE then MINIMUM_CHARGE - amount_due
      else 0
      end
      next unless excess.positive?

      credit = payments.credit.succeeded.sole
      credit.update! amount: credit.amount - excess, excess_amount: credit.excess_amount + excess
      refresh_paid_amount
      save!
    end
    refund_excess!
  end

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
    elsif paid? && payments.none?
      # Paid by a release that kept no ledger; recording this as excess would refund the payment that paid it.
      report_checkout_error session, UnrecordedPaymentError.new("Paid invoice has no recorded payments")
    else
      record_payment! kind: :checkout, amount: session.amount_total, stripe_payment_intent_id: session.payment_intent,
        stripe_checkout_session_id: session.id
    end
  end

  # A Checkout payment can succeed while its webhook is still being retried. It
  # paid the invoice, so it goes in before a manual payment can make it excess.
  def apply_paid_stored_checkout
    return if stripe_checkout_session_id.blank?

    session = Stripe::Checkout::Session.retrieve stripe_checkout_session_id
    apply_checkout_session session if session.status == "complete" && session.payment_status == "paid"
  rescue Stripe::StripeError => e
    Rails.error.report e, context: { invoice_id: id, session_id: stripe_checkout_session_id }
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

  def record_payment!(kind:, amount:, paid_on: Date.current, stripe_payment_intent_id: nil, stripe_checkout_session_id: nil)
    raise Invoice::InvalidStatusError, "Invoice must be sent to record a payment" unless sent? || paid?
    return :unchanged if stripe_payment_intent_id && payments.exists?(stripe_payment_intent_id:)

    kept = [ amount, amount_due ].min
    payments.create!(kind:, amount: kept, excess_amount: amount - kept, paid_on:, stripe_payment_intent_id:)
    refresh_paid_amount

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
    payments.awaiting_refund.find_each do |payment|
      intent = Stripe::PaymentIntent.retrieve id: payment.stripe_payment_intent_id, expand: [ "payment_method" ]
      params = { payment_intent: intent.id, amount: payment.excess_amount }
      params[:instructions_email] = client.email if intent.payment_method.type == "customer_balance"

      refund = Stripe::Refund.create params, { idempotency_key: "excess-#{payment.id}" }
      payment.update! stripe_refund_id: refund.id
    end
  end
end
