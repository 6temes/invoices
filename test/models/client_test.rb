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

  test "locale enum" do
    assert clients(:acme).en?
    assert clients(:sakura).ja?
  end

  test "payment_method enum" do
    assert clients(:acme).bank_transfer?
    assert clients(:sakura).credit_card?
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
end
