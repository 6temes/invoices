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
