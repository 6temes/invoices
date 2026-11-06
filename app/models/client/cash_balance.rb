module Client::CashBalance
  extend ActiveSupport::Concern

  CASH_BALANCE_RETURN_FEE = 275
  # Longer than a return's two Stripe calls take, so only a crashed return outlives it.
  CREDIT_RETURN_WINDOW = 10.minutes

  CashBalanceTransferredError = Class.new(StandardError)

  included do
    # Keyed on the credit last emailed, so a link dies once newer credit is announced
    # or a return empties the balance.
    generates_token_for :credit_refund, expires_in: Invoice::PAYMENT_LINK_VALIDITY do
      credit_notified_amount
    end
  end

  class_methods do
    def notice_cash_balance_transaction(transaction)
      client = find_by(stripe_customer_id: transaction.customer)
      return unless client

      case transaction.type
      when "return_canceled"
        client.release_return_fee!
      when "transferred_to_balance"
        # Stripe gives unclaimed credit to the account after 90 days; only the owner can return it now.
        Rails.error.report CashBalanceTransferredError.new("Unclaimed cash balance moved to the account balance"),
          context: { client_id: client.id, transaction_id: transaction.id, amount: transaction.net_amount }, handled: true
      end

      CashBalanceSettlementJob.perform_later client
    end

    # The client whose credit return began after the page carrying this receipt
    # was shown, so a repeat submit of that page.
    def find_by_credit_return_receipt(receipt)
      id, shown_at = credit_return_receipts.verified(receipt)
      client = find_by(id:) if id
      client if client&.returned_credit_since?(Time.zone.at(shown_at))
    end

    def credit_return_receipts
      Rails.application.message_verifier(:credit_return_receipt)
    end
  end

  # Settlement waits while Stripe is funding a bank transfer, because Stripe puts
  # every new yen towards it and the two would compete for the same money. It
  # also waits out a credit return, whose fee sits in the balance until charged.
  def settle_cash_balance!
    return settle_cash_balance_later(wait_until: credit_return_started_at + CREDIT_RETURN_WINDOW) if credit_return_in_flight?

    replay_balance_draws
    balance = cash_balance
    return if balance.positive? && awaiting_bank_transfer?

    invoices = balance_candidates(balance)
    drawn = invoices.sum do |invoice|
      next 0 if balance < Invoice::Payable::MINIMUM_CHARGE

      invoice.apply_balance!(balance).tap { balance -= it }
    end

    notice_credit drawn.positive? ? cash_balance : balance
  end

  # A cancelled return gives back the refund but not the fee Stripe charged for it.
  # The event names neither, so the newest fee charge is checked.
  def release_return_fee!
    fee = payment_intents.find { it.status == "succeeded" && it.metadata["credit_return_refund"] }
    return if fee.nil? || fee.metadata["credit_return_waived_for"]

    refund = Stripe::Refund.retrieve fee.metadata["credit_return_refund"]
    update! prepaid_return_fee_payment_intent_id: fee.id if refund.status == "canceled"
  end

  # A return cancelled after Stripe's 45 days leaves the fee already charged, so
  # the next return is free.
  def return_fee
    prepaid_return_fee_payment_intent_id ? 0 : CASH_BALANCE_RETURN_FEE
  end

  # A return is offered only when the client gets back at least the fee itself.
  def minimum_returnable_balance
    return_fee + CASH_BALANCE_RETURN_FEE
  end

  def returnable_credit(balance)
    balance >= minimum_returnable_balance ? balance - return_fee : 0
  end

  # The refund goes first, so a failed fee charge leaves the fee as credit rather
  # than charging the client for a return that never started. The keys follow the
  # balance's newest transaction: a double submit replays, while the same amount
  # arriving again later is a new return.
  def refund_cash_balance!(shown_balance)
    return :started if credit_return_in_flight?

    balance = cash_balance
    return :changed unless balance == shown_balance
    returnable = returnable_credit(balance)
    return :nothing_to_return if returnable.zero?
    return :started unless claim_credit_return

    begin
      fee = return_fee
      key = "#{id}-#{latest_cash_balance_transaction_id}"
      refund = Stripe::Refund.create(
        { origin: "customer_balance", customer: stripe_customer_id, amount: returnable, currency: Invoice::Payable::CURRENCY, instructions_email: email },
        { idempotency_key: "return-#{key}" }
      )
      update! credit_returned_at: credit_return_started_at, credit_notified_amount: 0
      settle_return_fee(fee, refund, key)
    ensure
      update! credit_return_started_at: nil
    end
  end

  def credit_return_in_flight?
    credit_return_started_at&.after?(CREDIT_RETURN_WINDOW.ago)
  end

  def returned_credit_since?(time)
    credit_return_in_flight? || (credit_returned_at.present? && credit_returned_at >= time)
  end

  def credit_return_receipt
    self.class.credit_return_receipts.generate [ id, Time.current.to_i ], expires_in: 1.hour
  end

  def settle_cash_balance_later(wait_until: nil)
    CashBalanceSettlementJob.set(wait_until:).perform_later self if stripe?
  end

  private

  def replay_balance_draws
    invoices.sent.where(id: InvoicePayment.balance.pending.select(:invoice_id)).each { it.apply_balance!(0) }
  end

  def awaiting_bank_transfer?
    payment_intents.any? do
      it.status == "requires_action" && it["next_action"]&.[]("type") == "display_bank_transfer_instructions"
    end
  end

  def payment_intents
    Stripe::PaymentIntent.list(customer: stripe_customer_id, limit: 100).auto_paging_each
  end

  def latest_cash_balance_transaction_id
    Stripe::Customer.list_cash_balance_transactions(stripe_customer_id, limit: 1).data.first.id
  end

  # An exact match goes first; the rest follow oldest first, so an exact match
  # that takes nothing (a Checkout payment under way) leaves the balance to them.
  def balance_candidates(balance)
    oldest_first = invoices.sent.order(:issue_date, :invoice_number).to_a
    exact = oldest_first.select { it.amount_due == balance }
    exact.one? ? exact + (oldest_first - exact) : oldest_first
  end

  def notice_credit(leftover)
    # Settlement never draws under the minimum charge, so announcing it would
    # promise a deduction that never comes.
    leftover = 0 if leftover < Invoice::Payable::MINIMUM_CHARGE
    # A delivery under way may still spend the credit.
    return if leftover.positive? && delivery_in_progress?
    return if credit_notified_amount == leftover

    noticed = with_lock do
      next false if credit_notified_amount == leftover

      update! credit_notified_amount: leftover
      leftover.positive?
    end

    InvoiceMailer.send_credit_notice(self, leftover).deliver_later if noticed
  end

  def delivery_in_progress?
    invoices.preparing.or(invoices.failed.where(id: InvoicePayment.credit.succeeded.select(:invoice_id))).exists?
  end

  def claim_credit_return
    with_lock do
      next false if credit_return_in_flight?

      update! credit_return_started_at: Time.current
    end
  end

  # The refund is under way whatever happens here, so a fee failure is reported
  # rather than shown to the client as a failed return.
  def settle_return_fee(fee, refund, key)
    if fee.positive?
      charge_return_fee(fee, refund, key)
    else
      # Marked as spent, or cancelling this free return would make the next one free too.
      prepaid = prepaid_return_fee_payment_intent_id
      update! prepaid_return_fee_payment_intent_id: nil
      Stripe::PaymentIntent.update prepaid, metadata: { credit_return_waived_for: refund.id }
    end
    :returned
  rescue Stripe::StripeError => e
    Rails.error.report e, severity: :error, context: { client_id: id, refund_id: refund.id, fee: }
    :started
  end

  def charge_return_fee(fee, refund, key)
    intent = Stripe::PaymentIntent.create({
      amount: fee,
      currency: Invoice::Payable::CURRENCY,
      customer: stripe_customer_id,
      automatic_payment_methods: { enabled: true, allow_redirects: "never" },
      payment_method_data: { type: "customer_balance" },
      confirm: true,
      metadata: { credit_return_refund: refund.id }
    }, { idempotency_key: "return-fee-#{key}" })

    # Left waiting, Stripe would collect the fee from the client's next transfer.
    Stripe::PaymentIntent.cancel intent.id if intent.status == "requires_action"
  end
end
