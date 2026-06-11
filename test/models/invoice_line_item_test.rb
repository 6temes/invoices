require "test_helper"

class InvoiceLineItemTest < ActiveSupport::TestCase
  test "validates required fields" do
    item = InvoiceLineItem.new
    assert_not item.valid?
    assert item.errors[:item_type].any?
    assert item.errors[:description].any?
    assert item.errors[:quantity].any?
    assert item.errors[:unit_price].any?
  end

  test "quantity must be greater than zero" do
    item = invoice_line_items(:acme_january_retainer)
    item.quantity = 0
    assert_not item.valid?
    assert item.errors[:quantity].any?
  end

  test "unit_price must be non-negative" do
    item = invoice_line_items(:acme_january_retainer)
    item.unit_price = -1
    assert_not item.valid?
    assert item.errors[:unit_price].any?
  end

  test "calculate_amount on validation" do
    item = InvoiceLineItem.new(
      invoice: invoices(:acme_february_draft),
      item_type: "Service",
      description: "Test item",
      quantity: 2.5,
      unit_price: 10000
    )
    item.valid?
    assert_equal 25000, item.amount
  end

  test "calculate_amount uses floor for fractional amounts" do
    item = InvoiceLineItem.new(
      invoice: invoices(:acme_february_draft),
      item_type: "Service",
      description: "Test item",
      quantity: 1.5,
      unit_price: 3333
    )
    item.valid?
    # 1.5 * 3333 = 4999.5 → floor → 4999
    assert_equal 4999, item.amount
  end

  test "cannot destroy line item with linked extra hours" do
    line_item = invoice_line_items(:acme_january_retainer)
    assert_not line_item.destroy
    assert line_item.errors[:base].any?
  end
end
