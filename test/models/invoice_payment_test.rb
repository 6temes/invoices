require "test_helper"
require Rails.root.join("db/migrate/20261101100100_backfill_invoice_payments")

class InvoicePaymentTest < ActiveSupport::TestCase
  test "backfill records one payment per paid invoice, for what was paid" do
    InvoicePayment.delete_all
    Invoice.where(id: invoices(:sakura_january)).update_all status: "paid", paid_on: Date.new(2026, 2, 10),
      paid_amount: 247_500, stripe_payment_intent_id: "pi_backfilled"

    ActiveRecord::Migration.suppress_messages { BackfillInvoicePayments.new.up }

    acme = invoices(:acme_january).payments.sole
    assert_equal [ "manual", 110_000 ], [ acme.kind, acme.amount ]
    sakura = invoices(:sakura_january).payments.sole
    assert_equal [ "checkout", 247_500, "pi_backfilled", Date.new(2026, 2, 10) ],
      [ sakura.kind, sakura.amount, sakura.stripe_payment_intent_id, sakura.paid_on ]
    assert_empty invoices(:acme_february_draft).payments

    assert_no_difference -> { InvoicePayment.count } do
      ActiveRecord::Migration.suppress_messages { BackfillInvoicePayments.new.up }
    end

    ActiveRecord::Migration.suppress_messages { BackfillInvoicePayments.new.down }
    assert_equal 0, InvoicePayment.count
  end

  test "refund status follows the excess and its refund" do
    payment = invoices(:sakura_january).payments.build(kind: :checkout, amount: 1_000)
    assert_nil payment.refund_status

    payment.excess_amount = 5_000
    assert_equal "awaiting", payment.refund_status

    payment.stripe_refund_id = "re_test"
    assert_equal "issued", payment.refund_status
  end

  test "payments awaiting a refund are the ones the refund run picks up" do
    invoice = invoices(:sakura_january)
    invoice.payments.create! kind: :checkout, amount: 1_000, excess_amount: 500, stripe_payment_intent_id: "pi_test_awaiting"
    invoice.payments.create! kind: :checkout, amount: 1_000, excess_amount: 500, stripe_payment_intent_id: "pi_test_issued",
      stripe_refund_id: "re_test_issued"

    assert_equal InvoicePayment.where(excess_amount: 1..).select { it.refund_status == "awaiting" }.sort,
      InvoicePayment.awaiting_refund.sort
  end

  test "a PaymentIntent is recorded once" do
    invoice = invoices(:sakura_january)
    invoice.payments.create! kind: :checkout, amount: 1_000, stripe_payment_intent_id: "pi_once"

    assert_raises ActiveRecord::RecordNotUnique do
      invoice.payments.create! kind: :checkout, amount: 1_000, stripe_payment_intent_id: "pi_once"
    end
  end

  test "a draft holds only credit kept from a reverted delivery" do
    draft = invoices(:acme_february_draft)

    %w[ balance checkout manual ].each do |kind|
      assert_not draft.payments.build(kind:, amount: 1_000).valid?, kind
    end
    assert draft.payments.build(kind: "credit", amount: 1_000).valid?
  end
end
