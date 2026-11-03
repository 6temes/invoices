require "test_helper"

class InvoicePaymentTest < ActiveSupport::TestCase
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
