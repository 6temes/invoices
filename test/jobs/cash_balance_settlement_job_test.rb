require "test_helper"

class CashBalanceSettlementJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @client = clients(:sakura)
    @older = invoices(:sakura_january)
    attach_deliverables @older
    @newer = invoices(:acme_february_draft).tap do |invoice|
      invoice.update_columns client_id: @client.id, status: "sent", sent_at: Time.current
      attach_deliverables invoice
    end
    stub_intents
  end

  test "an empty balance draws nothing and forgets the credit last announced" do
    @client.update! credit_notified_amount: 4_000
    stub_cash_balance 0
    Stripe::PaymentIntent.expects(:create).never

    assert_no_enqueued_emails { perform }
    assert_equal 0, @client.reload.credit_notified_amount
  end

  test "a bank transfer Stripe is still funding stops the run" do
    stub_cash_balance 300_000
    stub_intents Stripe::PaymentIntent.construct_from(id: "pi_waiting", status: "requires_action",
      next_action: { type: "display_bank_transfer_instructions" })
    Stripe::PaymentIntent.expects(:create).never

    assert_no_enqueued_emails { perform }
  end

  test "the balance pays the oldest invoice first and leaves the rest on the next one" do
    stub_cash_balance 300_000, 0
    stub_draws 247_500, 52_500

    perform

    assert @older.reload.paid?
    assert_equal 52_500, @newer.reload.paid_amount
    assert_equal %w[ balance ], @newer.payments.succeeded.pluck(:kind)
    assert_enqueued_email_with InvoiceMailer, :send_receipt, args: [ @older ]
    assert_enqueued_email_with InvoiceMailer, :send_partial_payment,
      args: [ @newer, { amount_received: 52_500, amount_remaining: 57_500 } ]
    assert_enqueued_emails 2
  end

  test "a balance equal to one invoice's amount due pays that invoice, even when it is not the oldest" do
    stub_cash_balance 110_000, 0
    stub_draws 110_000

    perform

    assert @newer.reload.paid?
    assert_equal 0, @older.reload.paid_amount
  end

  test "two invoices due the same amount fall back to the oldest" do
    @newer.update_columns total: @older.total
    stub_cash_balance 247_500, 0
    stub_draws 247_500

    perform

    assert @older.reload.paid?
    assert_not @newer.reload.paid?
  end

  test "an invoice already part paid draws only what is still due" do
    @older.payments.create! kind: :manual, amount: 200_000
    @older.update_columns paid_amount: 200_000
    @newer.destroy!
    stub_cash_balance 100_000, 52_500
    stub_draws 47_500

    perform

    assert @older.reload.paid?
  end

  test "an open Checkout session is expired before the balance pays the invoice" do
    @newer.destroy!
    @older.update_columns stripe_checkout_session_id: "cs_open"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_open").returns(Stripe::Checkout::Session.construct_from(id: "cs_open", status: "open"))
    Stripe::Checkout::Session.expects(:expire).with("cs_open")
    stub_cash_balance 247_500, 0
    stub_draws 247_500

    perform

    assert @older.reload.paid?
    assert_nil @older.stripe_checkout_session_id
  end

  test "an invoice with a completed Checkout session waits for that payment" do
    @older.update_columns stripe_checkout_session_id: "cs_complete"
    Stripe::Checkout::Session.stubs(:retrieve).with("cs_complete")
      .returns(Stripe::Checkout::Session.construct_from(id: "cs_complete", status: "complete"))
    stub_cash_balance 300_000, 190_000
    stub_draws 110_000

    perform

    assert_equal 0, @older.reload.paid_amount
    assert @newer.reload.paid?
  end

  test "a balance too small to charge leaves an open Checkout session alone" do
    @older.update_columns stripe_checkout_session_id: "cs_open"
    Stripe::Checkout::Session.expects(:retrieve).never
    stub_cash_balance 30
    Stripe::PaymentIntent.expects(:create).never

    perform
  end

  test "leftover credit is announced once, with the return link" do
    @older.update_columns status: "paid", paid_amount: @older.total
    @newer.update_columns status: "paid", paid_amount: @newer.total
    stub_cash_balance 10_000

    assert_enqueued_email_with(InvoiceMailer, :send_credit_notice, args: [ @client, 10_000 ]) { perform }
    assert_equal 10_000, @client.reload.credit_notified_amount
    assert_no_enqueued_emails { perform }
  end

  test "leftover credit waits while an invoice is being delivered" do
    @older.update_columns status: "paid", paid_amount: @older.total
    @newer.update_columns status: "preparing"
    stub_cash_balance 10_000

    assert_no_enqueued_emails { perform }
    assert_equal 0, @client.reload.credit_notified_amount
  end

  test "leftover credit waits while a failed delivery holds credit" do
    @older.update_columns status: "paid", paid_amount: @older.total
    @newer.payments.create! kind: :credit, amount: 5_000, stripe_payment_intent_id: "pi_kept"
    @newer.update_columns status: "failed", paid_amount: 5_000
    stub_cash_balance 10_000

    assert_no_enqueued_emails { perform }
  end

  test "a draw interrupted before it was recorded is replayed, though Stripe already took the balance" do
    @newer.destroy!
    payment = @older.payments.create! kind: :balance, status: :pending, amount: 247_500
    payment.update! idempotency_key: "invoice-payment-#{payment.id}"
    stub_cash_balance 0
    Stripe::PaymentIntent.expects(:create).with { |params, options| params[:amount] == 247_500 && options[:idempotency_key] == payment.idempotency_key }
      .returns(Stripe::PaymentIntent.construct_from(id: "pi_replayed", status: "succeeded"))

    perform

    assert @older.reload.paid?
    assert_enqueued_email_with InvoiceMailer, :send_receipt, args: [ @older ]
  end

  test "a Stripe outage is retried" do
    Stripe::Customer.stubs(:retrieve).raises(Stripe::APIConnectionError.new("timeout"))

    assert_enqueued_with(job: CashBalanceSettlementJob) { perform }
  end

  private

  def perform
    CashBalanceSettlementJob.perform_now @client
  end

  def stub_cash_balance(*amounts)
    customers = amounts.map { Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: it } }) }
    Stripe::Customer.stubs(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ]).returns(*customers)
  end

  def stub_intents(*intents)
    Stripe::PaymentIntent.stubs(:list).with(customer: "cus_test_sakura123", limit: 100)
      .returns(Stripe::ListObject.construct_from(object: "list", data: intents, has_more: false))
  end

  def stub_draws(*amounts)
    amounts.each_with_index do |amount, index|
      Stripe::PaymentIntent.expects(:create).with { |params, _| params[:amount] == amount && params[:payment_method_data] == { type: "customer_balance" } }
        .returns(Stripe::PaymentIntent.construct_from(id: "pi_balance_#{index}", status: "succeeded"))
    end
  end
end
