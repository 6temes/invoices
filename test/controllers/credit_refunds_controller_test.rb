require "test_helper"

class CreditRefundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = clients(:sakura)
    @client.update! credit_notified_amount: 10_000
    @token = @client.generate_token_for(:credit_refund)
  end

  test "show offers the credit less the fee in the client's language" do
    stub_cash_balance 10_000

    get credit_refund_path(@token)

    assert_response :success
    assert_select ".pending-figures dd", text: "¥10,000"
    assert_select ".pending-figures dd", text: "¥275"
    assert_select ".payment-amount .summary-card-value", text: "¥9,725"
    assert_select "form input[name=balance][value='10000']"
    assert_select "h1", text: "クレジットのご返金"
    assert_select "script", count: 0
  end

  test "show offers nothing when the balance does not cover the fee" do
    stub_cash_balance 200

    get credit_refund_path(@token)

    assert_response :success
    assert_select "form", count: 0
    assert_match "¥200", response.body
  end

  test "show offers nothing when the balance is empty" do
    stub_cash_balance 0

    get credit_refund_path(@token)

    assert_response :success
    assert_select "form", count: 0
  end

  test "show leaves out the fee when a cancelled return already paid it" do
    @client.update! prepaid_return_fee_payment_intent_id: "pi_fee_earlier"
    stub_cash_balance 9_725

    get credit_refund_path(@token)

    assert_select ".payment-amount .summary-card-value", text: "¥9,725"
    assert_select ".pending-figures dd", text: "¥0"
  end

  test "a link issued before the credit changed is no longer valid" do
    @client.update! credit_notified_amount: 4_000

    get credit_refund_path(@token)

    assert_response :not_found
    assert_select "h1", text: /no longer valid/
  end

  test "an expired link is no longer valid" do
    travel Invoice::PAYMENT_LINK_VALIDITY + 1.day do
      get credit_refund_path(@token)
    end

    assert_response :not_found
  end

  test "submitting returns the credit and confirms that Stripe will ask for bank details" do
    stub_cash_balance 10_000
    Stripe::Refund.expects(:create).with { |params, _| params[:amount] == 9_725 }.returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.expects(:create).with { |params, _| params[:amount] == 275 }
      .returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded"))

    post credit_refund_path(@token), params: { balance: 10_000 }

    assert_response :success
    assert_match "¥9,725", response.body
    assert_match "keiri@sakura.example.jp", response.body
  end

  test "submitting after the balance changed shows the new figures without returning anything" do
    stub_cash_balance 12_000
    Stripe::Refund.expects(:create).never

    post credit_refund_path(@token), params: { balance: 10_000 }

    assert_response :unprocessable_entity
    assert_select ".flash-alert"
    assert_select ".payment-amount .summary-card-value", text: "¥11,725"
  end

  test "a Stripe failure is reported and shown as a processing error" do
    stub_cash_balance 10_000
    Stripe::Refund.stubs(:create).raises(Stripe::APIConnectionError.new("timeout"))

    assert_error_reported(Stripe::APIConnectionError) do
      post credit_refund_path(@token), params: { balance: 10_000 }
    end

    assert_redirected_to credit_refund_path(@token)
    assert_equal I18n.t("invoice.payment_error", locale: :ja), flash[:alert]
  end

  test "a submission over the rate limit is turned away without touching Stripe" do
    # The test cache is a null store, so it reports the count a sixth post would reach.
    ActiveSupport::Cache::NullStore.any_instance.stubs(:increment).returns(6)
    Stripe::Customer.expects(:retrieve).never

    post credit_refund_path(@token), params: { balance: 10_000 }

    assert_redirected_to credit_refund_path(@token)
    assert flash[:alert].present?
  end

  private

  def stub_cash_balance(amount)
    Stripe::Customer.stubs(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ])
      .returns(Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: amount } }))
    Stripe::Customer.stubs(:list_cash_balance_transactions).with("cus_test_sakura123", limit: 1)
      .returns(Stripe::ListObject.construct_from(object: "list", data: [ { id: "ccsbtxn_latest" } ], has_more: false))
  end
end
