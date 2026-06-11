require "test_helper"

class BusinessTest < ActiveSupport::TestCase
  test "instance returns existing business" do
    assert_equal businesses(:default), Business.instance
  end

  test "instance raises when none exists" do
    Business.delete_all
    Current.reset
    assert_raises ActiveRecord::RecordNotFound do
      Business.instance
    end
  end

  test "singleton_guard prevents second business" do
    second = Business.new(businesses(:default).attributes.except("id"))
    assert_not second.valid?
    assert_includes second.errors[:base], "only one Business record is allowed"
  end

  test "validates required fields" do
    business = Business.new
    assert_not business.valid?
    assert business.errors[:name].any?
    assert business.errors[:tax_registration_number].any?
    assert business.errors[:bank_name].any?
    assert business.errors[:bank_branch].any?
    assert business.errors[:bank_account_holder].any?
    assert business.errors[:bank_account_type].any?
    assert business.errors[:bank_account_number].any?
    assert business.errors[:email].any?
    assert business.errors[:tax_rate].any?
    assert business.errors[:next_invoice_number].any?
  end

  test "tax_rate must be greater than zero" do
    business = businesses(:default)
    business.tax_rate = 0
    assert_not business.valid?
    assert business.errors[:tax_rate].any?
  end

  test "next_invoice_number must be greater than zero" do
    business = businesses(:default)
    business.next_invoice_number = 0
    assert_not business.valid?
    assert business.errors[:next_invoice_number].any?
  end

  test "has one address" do
    business = businesses(:default)
    assert_equal addresses(:business_address), business.address
  end
end
