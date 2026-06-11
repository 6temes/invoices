require "test_helper"
require "ostruct"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invoice = invoices(:sakura_january)
    @invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    @invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
  end

  test "valid checkout.session.completed marks invoice as paid" do
    event = build_stripe_event(
      type: "checkout.session.completed",
      invoice_id: @invoice.id,
      currency: "jpy",
      amount_total: @invoice.total,
      session_id: "cs_test_123",
      payment_intent: "pi_test_456"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    @invoice.reload
    assert @invoice.paid?
    assert_equal @invoice.total, @invoice.paid_amount
    assert_equal "cs_test_123", @invoice.stripe_checkout_session_id
    assert_equal "pi_test_456", @invoice.stripe_payment_intent_id
  end

  test "invalid signature returns bad_request" do
    stub_stripe_construct_event_error do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :bad_request
  end

  test "already paid invoice is skipped" do
    invoice = invoices(:acme_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    assert invoice.paid?

    original_paid_on = invoice.paid_on

    event = build_stripe_event(
      type: "checkout.session.completed",
      invoice_id: invoice.id,
      currency: "jpy",
      amount_total: invoice.total,
      session_id: "cs_test_789",
      payment_intent: "pi_test_abc"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    invoice.reload
    assert_equal original_paid_on, invoice.paid_on
    assert_nil invoice.stripe_checkout_session_id
  end

  test "mismatched currency is rejected" do
    event = build_stripe_event(
      type: "checkout.session.completed",
      invoice_id: @invoice.id,
      currency: "usd",
      amount_total: @invoice.total,
      session_id: "cs_test_999",
      payment_intent: "pi_test_999"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    @invoice.reload
    assert @invoice.sent?
  end

  test "mismatched amount is rejected" do
    event = build_stripe_event(
      type: "checkout.session.completed",
      invoice_id: @invoice.id,
      currency: "jpy",
      amount_total: 1,
      session_id: "cs_test_000",
      payment_intent: "pi_test_000"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    @invoice.reload
    assert @invoice.sent?
  end

  test "checkout.session.expired clears session ID when it matches" do
    @invoice.update_columns stripe_checkout_session_id: "cs_test_expired"

    event = build_stripe_event(
      type: "checkout.session.expired",
      invoice_id: @invoice.id,
      session_id: "cs_test_expired"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    assert_nil @invoice.reload.stripe_checkout_session_id
  end

  test "checkout.session.expired skips when session ID does not match" do
    @invoice.update_columns stripe_checkout_session_id: "cs_test_newer"

    event = build_stripe_event(
      type: "checkout.session.expired",
      invoice_id: @invoice.id,
      session_id: "cs_test_old"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    assert_equal "cs_test_newer", @invoice.reload.stripe_checkout_session_id
  end

  test "checkout.session.expired skips paid invoices" do
    invoice = invoices(:acme_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.update_columns stripe_checkout_session_id: "cs_test_paid"

    event = build_stripe_event(
      type: "checkout.session.expired",
      invoice_id: invoice.id,
      session_id: "cs_test_paid"
    )

    stub_stripe_construct_event(event) do
      post webhooks_stripe_path, params: "{}", headers: stripe_headers
    end

    assert_response :ok
    assert_equal "cs_test_paid", invoice.reload.stripe_checkout_session_id
  end

  private

  def stripe_headers
    { "HTTP_STRIPE_SIGNATURE" => "t=123,v1=abc" }
  end

  def build_stripe_event(type:, invoice_id:, currency: nil, amount_total: nil, session_id: nil, payment_intent: nil)
    session = OpenStruct.new(
      metadata: { "invoice_id" => invoice_id.to_s },
      currency:,
      amount_total:,
      id: session_id,
      payment_intent:
    )

    OpenStruct.new(type:, data: OpenStruct.new(object: session))
  end

  def stub_stripe_construct_event(event)
    original = Stripe::Webhook.method(:construct_event)
    Stripe::Webhook.define_singleton_method(:construct_event) { |*| event }
    yield
  ensure
    Stripe::Webhook.define_singleton_method(:construct_event, original)
  end

  def stub_stripe_construct_event_error
    original = Stripe::Webhook.method(:construct_event)
    Stripe::Webhook.define_singleton_method(:construct_event) { |*| raise Stripe::SignatureVerificationError.new("invalid", "sig") }
    yield
  ensure
    Stripe::Webhook.define_singleton_method(:construct_event, original)
  end
end
