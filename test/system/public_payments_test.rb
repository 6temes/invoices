require "application_system_test_case"

class PublicPaymentsSystemTest < ApplicationSystemTestCase
  test "a client whose bank transfer arrived short sees what is still due and where to send it" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns locale: "en", stripe_checkout_session_id: "cs_test_transfer"
    Stripe::Checkout::Session.stubs(:retrieve).returns(Stripe::Checkout::Session.construct_from(
      id: "cs_test_transfer", status: "complete", payment_status: "unpaid", currency: "jpy",
      amount_total: invoice.total, payment_intent: "pi_test_transfer", metadata: { invoice_id: invoice.id.to_s }))
    Stripe::PaymentIntent.stubs(:retrieve).returns(Stripe::PaymentIntent.construct_from(
      id: "pi_test_transfer", status: "requires_action", amount: 247_500,
      next_action: { type: "display_bank_transfer_instructions", display_bank_transfer_instructions: {
        amount_remaining: 440, hosted_instructions_url: "https://payments.stripe.com/bank_transfers/instructions/test_example",
        financial_addresses: [ { type: "zengin", zengin: {
          bank_name: "Example Bank", branch_name: "Sample Branch", account_type: "futsu",
          account_number: "7654321", account_holder_name: "Example Consulting" } } ] } }))

    visit public_payment_path(token: invoice.signed_id(purpose: :payment, expires_in: 60.days))

    assert_text "STILL DUE"
    assert_text "¥440"
    assert_text "¥247,060"
    assert_text "Part of your transfer has arrived."
    assert_link "View the transfer instructions", href: "https://payments.stripe.com/bank_transfers/instructions/test_example"
    assert_no_button "Pay now"
  end
end
