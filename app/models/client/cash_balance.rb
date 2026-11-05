module Client::CashBalance
  extend ActiveSupport::Concern

  CASH_BALANCE_RETURN_FEE = 275

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
  end

  # Settlement waits while Stripe is funding a bank transfer, because Stripe puts
  # every new yen towards it and the two would compete for the same money.
  def settle_cash_balance!
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

  def returnable_credit(balance)
    balance > return_fee ? balance - return_fee : 0
  end

  # The refund goes first, so a failed fee charge leaves the fee as credit rather
  # than charging the client for a return that never started. The keys follow the
  # balance's newest transaction: a double submit replays, while the same amount
  # arriving again later is a new return.
  def refund_cash_balance!(shown_balance)
    balance = cash_balance
    return :changed unless balance == shown_balance
    returnable = returnable_credit(balance)
    return :nothing_to_return if returnable.zero?

    fee = return_fee
    key = "#{id}-#{latest_cash_balance_transaction_id}"
    refund = Stripe::Refund.create(
      { origin: "customer_balance", customer: stripe_customer_id, amount: returnable, currency: Invoice::Payable::CURRENCY, instructions_email: email },
      { idempotency_key: "return-#{key}" }
    )

    if fee.positive?
      charge_return_fee(fee, refund, key)
    else
      # Marked as spent, or cancelling this free return would make the next one free too.
      Stripe::PaymentIntent.update prepaid_return_fee_payment_intent_id, metadata: { credit_return_waived_for: refund.id }
      update! prepaid_return_fee_payment_intent_id: nil
    end
    update! credit_notified_amount: 0
    :returned
  end

  def settle_cash_balance_later
    CashBalanceSettlementJob.perform_later self if stripe?
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

  def balance_candidates(balance)
    oldest_first = invoices.sent.order(:issue_date, :invoice_number).to_a
    exact = oldest_first.select { it.amount_due == balance }
    exact.one? ? exact : oldest_first
  end

  def notice_credit(leftover)
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
