require "test_helper"

class TokenLoggingTest < ActionDispatch::IntegrationTest
  setup do
    @logger = SemanticLogger::Test::CaptureLogEvents.new
    ActionController::Base.stubs(:logger).returns(@logger)
  end

  test "request logs leave out the token in a payment link" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)

    get public_payment_path(token:)

    assert_response :success
    assert_logged_without token
  end

  test "request logs leave out a payment link token that arrives percent-encoded" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)

    get "/pay/#{token.sub("--", "%2D%2D")}"

    assert_response :success
    assert_logged_without token.split("--").first
  end

  test "request logs leave out the token in a credit link" do
    client = clients(:sakura)
    client.update! credit_notified_amount: 10_000
    token = client.generate_token_for(:credit_refund)
    client.update! credit_notified_amount: 4_000

    get credit_refund_path(token)

    assert_response :not_found

    assert_logged_without token
  end

  test "request logs leave out the Stripe Checkout address a payment redirects to" do
    invoice = invoices(:sakura_january)
    attach_deliverables invoice
    invoice.update_columns stripe_checkout_session_id: "cs_test_open"
    Stripe::Checkout::Session.stubs(:retrieve).returns(Stripe::Checkout::Session.construct_from(
      id: "cs_test_open", status: "open", url: "https://checkout.stripe.com/c/pay/cs_test_open"))

    post public_payment_create_path(invoice.signed_id(purpose: :payment, expires_in: 60.days))

    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_test_open"
    assert_logged_without "cs_test_open"
  end

  test "request logs leave out a password reset token, including in its redirect" do
    token = User.take.password_reset_token

    put password_path(token), params: { password: "a long new passphrase", password_confirmation: "a different passphrase" }

    assert_redirected_to edit_password_path(token)
    assert_logged_without token
  end

  private

  def assert_logged_without(token)
    assert_not_empty @logger.events
    @logger.events.each do |event|
      assert_not_includes [ event.message, event.payload ].to_json, token, "#{event.name}: #{event.message}"
    end
  end
end
