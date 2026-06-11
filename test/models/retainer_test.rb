require "test_helper"

class RetainerTest < ActiveSupport::TestCase
  test "validates required fields" do
    retainer = Retainer.new
    assert_not retainer.valid?
    assert retainer.errors[:monthly_hours].any?
    assert retainer.errors[:monthly_amount].any?
    assert retainer.errors[:hourly_rate].any?
    assert retainer.errors[:starts_on].any?
  end

  test "numeric fields must be greater than zero" do
    retainer = retainers(:acme_active)
    retainer.monthly_hours = 0
    assert_not retainer.valid?

    retainer.reload
    retainer.monthly_amount = 0
    assert_not retainer.valid?

    retainer.reload
    retainer.hourly_rate = -1
    assert_not retainer.valid?
  end

  test "active scope returns retainers without end date that have started" do
    active = Retainer.active
    assert_includes active, retainers(:acme_active)
    assert_includes active, retainers(:sakura_active)
    assert_includes active, retainers(:fuji_active)
  end

  test "active scope excludes ended retainers" do
    retainers(:acme_active).update_columns ends_on: 1.day.ago
    assert_not_includes Retainer.active, retainers(:acme_active)
  end

  test "active scope excludes future retainers" do
    retainers(:acme_active).update_columns starts_on: 1.day.from_now
    assert_not_includes Retainer.active, retainers(:acme_active)
  end

  test "prevents overlapping open-ended retainer for same client" do
    duplicate = Retainer.new(
      client: clients(:acme),
      monthly_hours: 5,
      monthly_amount: 50000,
      hourly_rate: 10000,
      starts_on: Date.current
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:base], "overlaps with an existing retainer"
  end

  test "allows retainer for different client" do
    new_client = Client.create!(
      name: "New Client",
      contact_name: "New Person",
      email: "new@example.com",
      locale: :en,
      payment_method: :bank_transfer,
      payment_terms_days: 30,
      address_attributes: { country_code: "JP", postal_code: "100-0001", locality: "千代田区", administrative_area: "東京都" }
    )
    retainer = Retainer.new(
      client: new_client,
      monthly_hours: 10,
      monthly_amount: 100000,
      hourly_rate: 10000,
      starts_on: Date.current
    )
    assert retainer.valid?
  end

  test "allows non-overlapping closed retainer" do
    retainers(:acme_active).update_columns ends_on: 1.day.ago

    retainer = Retainer.new(
      client: clients(:acme),
      monthly_hours: 10,
      monthly_amount: 100000,
      hourly_rate: 10000,
      starts_on: Date.current
    )
    assert retainer.valid?
  end
end
