require "test_helper"

class AddressTest < ActiveSupport::TestCase
  test "validates required fields" do
    address = Address.new(country_code: nil)
    assert_not address.valid?
    assert address.errors[:country_code].any?
    assert address.errors[:postal_code].any?
  end

  test "defaults country_code to JP" do
    assert_equal "JP", Address.new.country_code
  end

  test "validates country_code is valid ISO 3166-1 alpha-2" do
    address = addresses(:business_address)
    address.country_code = "XX"
    assert_not address.valid?
    assert address.errors[:country_code].any?
  end

  test "belongs to addressable (polymorphic)" do
    assert_equal businesses(:default), addresses(:business_address).addressable
    assert_equal clients(:acme), addresses(:acme_address).addressable
  end

  # JP validation
  test "JP address requires locality" do
    address = addresses(:business_address)
    address.locality = nil
    assert_not address.valid?
    assert address.errors[:locality].any?
  end

  test "JP address without street is valid" do
    address = addresses(:business_address)
    address.street = nil
    assert address.valid?
  end

  test "JP address validates postal code format" do
    address = addresses(:business_address)

    address.postal_code = "150-0001"
    assert address.valid?

    address.postal_code = "1500001"
    assert address.valid?

    address.postal_code = "123"
    assert_not address.valid?
    assert address.errors[:postal_code].any?
  end

  test "JP address validates prefecture" do
    address = addresses(:business_address)
    address.administrative_area = "Invalid"
    assert_not address.valid?
    assert address.errors[:administrative_area].any?
  end

  test "JP address accepts valid prefecture" do
    address = addresses(:business_address)
    address.administrative_area = "東京都"
    assert address.valid?
  end

  test "JP address requires administrative_area" do
    address = addresses(:business_address)
    address.administrative_area = nil
    assert_not address.valid?
    assert address.errors[:administrative_area].any?
  end

  # ES validation
  test "ES address requires locality" do
    address = Address.new(
      country_code: "ES", postal_code: "08001", street: "Calle Example 1",
      administrative_area: "Barcelona", addressable: businesses(:default)
    )
    address.locality = nil
    assert_not address.valid?
    assert address.errors[:locality].any?
  end

  test "ES address requires street" do
    address = Address.new(
      country_code: "ES", postal_code: "08001", locality: "Barcelona",
      administrative_area: "Barcelona", addressable: businesses(:default)
    )
    assert_not address.valid?
    assert address.errors[:street].any?
  end

  test "ES address requires administrative_area" do
    address = Address.new(
      country_code: "ES", postal_code: "08001", street: "Calle Example 1",
      locality: "Barcelona", addressable: businesses(:default)
    )
    address.administrative_area = nil
    assert_not address.valid?
    assert address.errors[:administrative_area].any?
  end

  test "ES address validates postal code format" do
    address = Address.new(
      country_code: "ES", street: "Calle Example 1", locality: "Barcelona",
      administrative_area: "Barcelona", addressable: businesses(:default)
    )

    address.postal_code = "08001"
    assert address.valid?

    address.postal_code = "123"
    assert_not address.valid?
    assert address.errors[:postal_code].any?

    address.postal_code = "08001A"
    assert_not address.valid?
  end

  test "ES address validates province" do
    address = Address.new(
      country_code: "ES", postal_code: "08001", street: "Calle Example 1",
      locality: "Barcelona", addressable: businesses(:default)
    )

    address.administrative_area = "Barcelona"
    assert address.valid?

    address.administrative_area = "Invalid"
    assert_not address.valid?
    assert address.errors[:administrative_area].any?
  end

  # Generic validation
  test "generic address requires street" do
    address = addresses(:business_address)
    address.country_code = "US"
    address.street = nil
    assert_not address.valid?
    assert address.errors[:street].any?
  end

  test "generic address with street is valid" do
    address = addresses(:business_address)
    address.country_code = "US"
    address.administrative_area = nil
    address.locality = nil
    address.sublocality = nil
    address.street = "123 Main St"
    assert address.valid?
  end

  # fields_partial
  test "fields_partial returns es partial for ES" do
    assert_equal "addresses/es_fields", Address.new(country_code: "ES").fields_partial
  end

  test "fields_partial returns jp partial for JP" do
    assert_equal "addresses/jp_fields", Address.new(country_code: "JP").fields_partial
  end

  test "fields_partial returns generic partial for unknown country" do
    assert_equal "addresses/generic_fields", Address.new(country_code: "US").fields_partial
  end

  test "client requires address with valid postal code" do
    client = Client.new(
      name: "Test", contact_name: "Test Person", email: "t@t.com", locale: "en",
      payment_method: "bank_transfer", payment_terms_days: 30,
      address_attributes: { country_code: "JP" }
    )
    assert_not client.valid?
    assert client.errors[:"address.postal_code"].any? || client.errors[:address].any?
  end

  # formatted_lines
  test "formatted_lines for JP address" do
    address = addresses(:business_address)
    lines = address.formatted_lines
    assert_equal "〒150-0001", lines.first
    assert_includes lines[1], "東京都"
    assert_includes lines[1], "渋谷区"
  end

  test "formatted_lines for ES address" do
    address = Address.new(
      country_code: "ES",
      postal_code: "08001",
      street: "Calle Example 1, 2ºA",
      locality: "Barcelona",
      administrative_area: "Barcelona",
      addressable: businesses(:default)
    )
    lines = address.formatted_lines
    assert_equal "Calle Example 1, 2ºA", lines.first
    assert_equal "08001 Barcelona", lines[1]
    assert_equal "Barcelona", lines[2]
    assert_equal "España", lines.last
  end

  test "formatted_lines for generic address" do
    address = Address.new(
      country_code: "US",
      postal_code: "10001",
      street: "123 Main St",
      locality: "New York",
      administrative_area: "NY",
      addressable: businesses(:default)
    )
    lines = address.formatted_lines
    assert_equal "123 Main St", lines.first
    assert_includes lines[1], "New York"
    assert_includes lines[1], "NY"
    assert_equal "United States of America", lines.last
  end
end
