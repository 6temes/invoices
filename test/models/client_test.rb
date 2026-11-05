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
      { idempotency_key: "return-#{client.id}-ccsbtxn_latest" }
    ).returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.expects(:create).with do |params, options|
      params[:amount] == 275 && params[:customer] == "cus_test_sakura123" && params[:confirm] &&
        params[:payment_method_data] == { type: "customer_balance" } && params[:metadata] == { credit_return_refund: "rcb_return" } &&
        options == { idempotency_key: "return-fee-#{client.id}-ccsbtxn_latest" }
    end.returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded"))

    assert_equal :returned, client.refund_cash_balance!(10_000)
    assert_equal 0, client.reload.credit_notified_amount
  end

  test "the same balance returned again after new credit arrives is a new return, not a replay" do
    client = clients(:sakura)
    stub_cash_balance 10_000
    keys = []
    Stripe::Refund.stubs(:create).with { |_, options| keys << options[:idempotency_key] }.returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.stubs(:create).returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded"))

    client.refund_cash_balance!(10_000)
    stub_latest_cash_balance_transaction "ccsbtxn_newer"
    client.refund_cash_balance!(10_000)

    assert_equal [ "return-#{client.id}-ccsbtxn_latest", "return-#{client.id}-ccsbtxn_newer" ], keys
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
    Stripe::PaymentIntent.expects(:update).with("pi_fee_earlier", metadata: { credit_return_waived_for: "rcb_again" })

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

  test "a return holds settlement off until it ends, then records when it began" do
    client = clients(:sakura)
    stub_cash_balance 10_000
    Stripe::Refund.expects(:create).with do
      assert client.reload.credit_return_in_flight?
      true
    end.returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.stubs(:create).returns(Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded"))

    freeze_time do
      client.refund_cash_balance!(10_000)

      assert_not client.reload.credit_return_in_flight?
      assert_equal Time.current, client.credit_returned_at
    end
  end

  test "a second return while one is under way makes no Stripe call" do
    client = clients(:sakura)
    client.update! credit_return_started_at: 1.minute.ago
    Stripe::Customer.expects(:retrieve).never
    Stripe::Refund.expects(:create).never

    assert_equal :started, client.refund_cash_balance!(10_000)
  end

  test "a return whose marker outlived a crash no longer holds anything off" do
    client = clients(:sakura)
    client.update! credit_return_started_at: (Client::CREDIT_RETURN_WINDOW + 1.minute).ago

    assert_not client.credit_return_in_flight?
  end

  test "a fee charge that fails after the refund is reported, and the return still stands" do
    client = clients(:sakura)
    client.update! credit_notified_amount: 10_000
    stub_cash_balance 10_000
    Stripe::Refund.stubs(:create).returns(Stripe::Refund.construct_from(id: "rcb_return"))
    Stripe::PaymentIntent.stubs(:create).raises(Stripe::APIConnectionError.new("timeout"))

    assert_error_reported(Stripe::APIConnectionError) do
      assert_equal :started, client.refund_cash_balance!(10_000)
    end
    assert_equal 0, client.reload.credit_notified_amount
    assert_not client.credit_return_in_flight?
  end

  test "a return receipt names the client only once a return began after its page was shown" do
    client = clients(:sakura)
    receipt = client.credit_return_receipt

    assert_nil Client.find_by_credit_return_receipt(receipt)

    client.update! credit_returned_at: 1.second.from_now
    assert_equal client, Client.find_by_credit_return_receipt(receipt)

    client.update! credit_returned_at: 1.hour.ago
    assert_nil Client.find_by_credit_return_receipt(receipt)
    assert_nil Client.find_by_credit_return_receipt("forged")
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

  test "a fee that already paid for a free return is not released again" do
    client = clients(:sakura)
    stub_fee_charge refund_status: "canceled", waived: true

    client.release_return_fee!

    assert_nil client.reload.prepaid_return_fee_payment_intent_id
  end

  test "a return still on its way keeps the fee charged" do
    client = clients(:sakura)
    stub_fee_charge refund_status: "pending"

    client.release_return_fee!

    assert_nil client.reload.prepaid_return_fee_payment_intent_id
  end

  private

  def stub_fee_charge(refund_status:, waived: false)
    metadata = { credit_return_refund: "rcb_return", credit_return_waived_for: ("rcb_free" if waived) }.compact
    fee = Stripe::PaymentIntent.construct_from(id: "pi_fee", status: "succeeded", metadata:)
    draw = Stripe::PaymentIntent.construct_from(id: "pi_draw", status: "succeeded", metadata: { invoice_id: "1" })
    Stripe::PaymentIntent.stubs(:list).with(customer: "cus_test_sakura123", limit: 100)
      .returns(Stripe::ListObject.construct_from(object: "list", data: [ draw, fee ], has_more: false))
    Stripe::Refund.stubs(:retrieve).with("rcb_return").returns(Stripe::Refund.construct_from(id: "rcb_return", status: refund_status))
  end

  def stub_cash_balance(amount)
    Stripe::Customer.stubs(:retrieve).with(id: "cus_test_sakura123", expand: [ "cash_balance" ])
      .returns(Stripe::Customer.construct_from(id: "cus_test_sakura123", cash_balance: { available: { jpy: amount } }))
    stub_latest_cash_balance_transaction "ccsbtxn_latest"
  end

  def stub_latest_cash_balance_transaction(id)
    Stripe::Customer.stubs(:list_cash_balance_transactions).with("cus_test_sakura123", limit: 1)
      .returns(Stripe::ListObject.construct_from(object: "list", data: [ { id:, object: "customer_cash_balance_transaction" } ], has_more: false))
  end
end
