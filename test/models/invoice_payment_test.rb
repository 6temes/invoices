require "test_helper"

class InvoicePaymentTest < ActiveSupport::TestCase
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
