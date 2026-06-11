require "test_helper"
require "ostruct"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invoice = invoices(:sakura_january)
    @invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    @invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
    @token = @invoice.signed_id(purpose: :payment, expires_in: 60.days)
  end

  test "show renders payment page for sent invoice" do
    get public_payment_path(token: @token)

    assert_response :success
    assert_select "h1", text: /#{@invoice.invoice_number}/
  end

  test "show renders thank_you for paid invoice" do
    invoice = invoices(:acme_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)

    get public_payment_path(token:)

    assert_response :success
    assert_select "h1", text: /Thank you/i
  end

  test "invalid token returns not_found" do
    get public_payment_path(token: "invalid-token")

    assert_response :not_found
    assert_includes response.body, "Invalid or expired payment link"
  end

  test "expired token returns not_found" do
    token = @invoice.signed_id(purpose: :payment, expires_in: 0.seconds)

    travel 1.minute do
      get public_payment_path(token:)

      assert_response :not_found
      assert_includes response.body, "Invalid or expired payment link"
    end
  end

  test "token with wrong purpose returns not_found" do
    token = @invoice.signed_id(purpose: :wrong_purpose, expires_in: 60.days)

    get public_payment_path(token:)

    assert_response :not_found
  end

  test "create redirects to Stripe when session is open" do
    @invoice.update_columns stripe_checkout_session_id: "cs_test_open"

    open_session = OpenStruct.new(status: "open", id: "cs_test_open", url: "https://checkout.stripe.com/pay/cs_test_open")

    stub_stripe_session_retrieve(open_session) do
      post public_payment_create_path(@token)
    end

    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_open"
  end

  test "create recreates session when existing one is expired" do
    @invoice.update_columns stripe_checkout_session_id: "cs_test_expired_123"

    expired_session = OpenStruct.new(status: "expired", id: "cs_test_expired_123")
    new_session = OpenStruct.new(id: "cs_test_new_456", url: "https://checkout.stripe.com/new")

    stub_stripe_customer_retrieve do
      stub_stripe_session_retrieve(expired_session) do
        stub_stripe_session_create(new_session) do
          post public_payment_create_path(@token)
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.com/new"
    assert_equal "cs_test_new_456", @invoice.reload.stripe_checkout_session_id
  end

  test "create creates session when no session ID exists" do
    @invoice.update_columns stripe_checkout_session_id: nil

    new_session = OpenStruct.new(id: "cs_test_fresh", url: "https://checkout.stripe.com/fresh")

    stub_stripe_customer_retrieve do
      stub_stripe_session_create(new_session) do
        post public_payment_create_path(@token)
      end
    end

    assert_redirected_to "https://checkout.stripe.com/fresh"
    assert_equal "cs_test_fresh", @invoice.reload.stripe_checkout_session_id
  end

  test "create shows friendly error when Stripe API is down" do
    @invoice.update_columns stripe_checkout_session_id: nil

    stub_stripe_customer_retrieve do
      stub_stripe_session_create_error(Stripe::APIConnectionError.new("Connection failed")) do
        post public_payment_create_path(@token)
      end
    end

    assert_redirected_to public_payment_path(@token)
    assert_equal I18n.t("invoice.payment_error", locale: @invoice.locale), flash[:alert]
  end

  test "create redirects non-sent invoices without calling Stripe" do
    invoice = invoices(:acme_january)
    invoice.pdf.attach io: StringIO.new("%PDF-1.4"), filename: "test.pdf", content_type: "application/pdf"
    invoice.ubl_xml.attach io: StringIO.new("<Invoice/>"), filename: "test.xml", content_type: "application/xml"
    token = invoice.signed_id(purpose: :payment, expires_in: 60.days)

    post public_payment_create_path(token)

    assert_redirected_to public_payment_path(token)
  end

  private

  def stub_stripe_session_retrieve(session)
    original = Stripe::Checkout::Session.method(:retrieve)
    Stripe::Checkout::Session.define_singleton_method(:retrieve) { |*| session }
    yield
  ensure
    Stripe::Checkout::Session.define_singleton_method(:retrieve, original)
  end

  def stub_stripe_session_create(session)
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) { |*| session }
    yield
  ensure
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end

  def stub_stripe_customer_retrieve
    original = Stripe::Customer.method(:retrieve)
    Stripe::Customer.define_singleton_method(:retrieve) { |id, *| OpenStruct.new(id:) }
    yield
  ensure
    Stripe::Customer.define_singleton_method(:retrieve, original)
  end

  def stub_stripe_session_create_error(error)
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) { |*| raise error }
    yield
  ensure
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end
end
