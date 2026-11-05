require "test_helper"

class ClientTest < ActiveSupport::TestCase
  test "validates required fields" do
    client = Client.new
    assert_not client.valid?
    assert client.errors[:name].any?
    assert client.errors[:email].any?
    assert client.errors[:payment_terms_days].any?
  end

  test "payment_terms_days must be greater than zero" do
    client = clients(:acme)
    client.payment_terms_days = 0
    assert_not client.valid?
    assert client.errors[:payment_terms_days].any?
  end

  test "bank_transfer client must not have stripe_customer_id" do
    client = clients(:acme)
    assert client.bank_transfer?
    client.stripe_customer_id = "cus_test_bad"
    assert_not client.valid?
    assert client.errors[:stripe_customer_id].any?
  end

  test "cash_balance reads the customer's available yen" do
    Stripe::Customer.expects(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ])
      .returns(Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: 12_000 } }))

    assert_equal 12_000, clients(:sakura).cash_balance
  end

  test "cash_balance is zero without a yen balance or a Stripe customer" do
    Stripe::Customer.stubs(:retrieve).returns(Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: nil }))

    assert_equal 0, clients(:sakura).cash_balance
    assert_equal 0, clients(:acme).cash_balance
  end

  test "locale enum" do
    assert clients(:acme).en?
    assert clients(:sakura).ja?
  end

  test "payment_method enum" do
    assert clients(:acme).bank_transfer?
    assert clients(:sakura).stripe?
  end

  test "active_retainer returns the current retainer" do
    retainer = clients(:acme).active_retainer
    assert_equal retainers(:acme_active), retainer
  end

  test "active_retainer returns nil when none active" do
    retainers(:acme_active).update_columns ends_on: 1.day.ago
    assert_nil clients(:acme).active_retainer
  end

  test "github_repos returns deserialized array" do
    assert_equal [ "acme/web-app", "acme/api" ], clients(:acme).github_repos
  end

  test "github_repos defaults to empty array" do
    client = Client.new
    assert_equal [], client.github_repos
  end

  test "github_repos round-trips through assignment" do
    client = clients(:acme)
    client.github_repos = [ "new/repo", "another/repo" ]
    assert_equal [ "new/repo", "another/repo" ], client.github_repos
  end

  test "has many associations" do
    client = clients(:acme)
    assert client.retainers.any?
    assert client.invoices.any?
    assert client.extra_hours.any?
  end

  test "requires address" do
    client = clients(:acme)
    client.address.destroy
    client.reload
    assert_not client.valid?
    assert client.errors[:address].any?
  end

  test "client with address is valid" do
    assert clients(:acme).valid?
    assert clients(:sakura).valid?
    assert clients(:fuji).valid?
  end

  test "returning credit refunds the balance less the fee, then charges the fee from what is left" do
    client = clients(:sakura)
    client.update! credit_notified_amount: 10_000
    stub_cash_balance 10_000
    Stripe::Refund.expects(:create).with(
      { origin: "customer_balance", customer: "cus_test_sakura123", amount: 9_725, currency: "jpy", instructions_email: "keiri@sakura.example.jp" },
      { idempotency_key: "return-#{client.id}-10000-#{Date.current.iso8601}" }
    ).returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.expects(:create).with do |params, options|
      params[:amount] == 275 && params[:customer] == "cus_test_sakura123" && params[:confirm] &&
        params[:payment_method_data] == { type: "customer_balance" } && params[:metadata] == { credit_return_refund: "rcb_return" } &&
        options == { idempotency_key: "return-fee-#{client.id}-10000-#{Date.current.iso8601}" }
    end.returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded"))

    assert_equal :returned, client.refund_cash_balance!(10_000)
    assert_equal 0, client.reload.credit_notified_amount
  end

  test "returning credit makes no Stripe call when the balance moved since it was shown" do
    stub_cash_balance 12_000
    Stripe::Refund.expects(:create).never
    Stripe::PaymentIntent.expects(:create).never

    assert_equal :changed, clients(:sakura).refund_cash_balance!(10_000)
  end

  test "a balance at or below the fee has nothing to return" do
    stub_cash_balance 275
    Stripe::Refund.expects(:create).never

    client = clients(:sakura)
    assert_equal 0, client.returnable_credit(275)
    assert_equal :nothing_to_return, client.refund_cash_balance!(275)
  end

  test "a fee already paid on a cancelled return is not charged again" do
    client = clients(:sakura)
    client.update! prepaid_return_fee_payment_intent_id: "pi_fee_earlier"
    stub_cash_balance 9_725
    Stripe::Refund.expects(:create).with { |params, _| params[:amount] == 9_725 }.returns(Stripe::Refund.construct_from(id: "rcb_again"))
    Stripe::PaymentIntent.expects(:create).never

    assert_equal 0, client.return_fee
    assert_equal :returned, client.refund_cash_balance!(9_725)
    assert_nil client.reload.prepaid_return_fee_payment_intent_id
  end

  test "a fee charge left waiting for a transfer is cancelled rather than collected later" do
    stub_cash_balance 10_000
    Stripe::Refund.stubs(:create).returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.stubs(:create).returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "requires_action"))
    Stripe::PaymentIntent.expects(:cancel).with("pi_fee")

    assert_equal :returned, clients(:sakura).refund_cash_balance!(10_000)
  end

  test "a credit return link stops working once the notified credit changes" do
    client = clients(:sakura)
    client.update! credit_notified_amount: 10_000
    token = client.generate_token_for(:credit_refund)

    assert_equal client, Client.find_by_token_for(:credit_refund, token)

    client.update! credit_notified_amount: 4_000
    assert_nil Client.find_by_token_for(:credit_refund, token)
  end

  test "a cancelled return makes the next return free" do
    client = clients(:sakura)
    stub_fee_charge refund_status: "canceled"

    client.release_return_fee!

    assert_equal "pi_fee", client.reload.prepaid_return_fee_payment_intent_id
  end

  test "a return still on its way keeps the fee charged" do
    client = clients(:sakura)
    stub_fee_charge refund_status: "pending"

    client.release_return_fee!

    assert_nil client.reload.prepaid_return_fee_payment_intent_id
  end

  private

  def stub_fee_charge(refund_status:)
    fee = Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded", metadata: { credit_return_refund: "rcb_return" })
    draw = Stripe::PaymentIntent.construct_from(id: "pi_draw", status: "succeeded", metadata: { invoice_id: "1" })
    Stripe::PaymentIntent.stubs(:list).with(customer: "cus_test_sakura123", limit: 100)
      .returns(Stripe::ListObject.construct_from(object: "list", data: [ draw, fee ], has_more: false))
    Stripe::Refund.stubs(:retrieve).with("rcb_return").returns(Stripe::Refund.construct_from(id: "rcb_return", status: refund_status))
  end

  def stub_cash_balance(amount)
    Stripe::Customer.stubs(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ])
      .returns(Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: amount } }))
  end
end
