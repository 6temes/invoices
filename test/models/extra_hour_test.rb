require "test_helper"

class ExtraHourTest < ActiveSupport::TestCase
  test "validates required fields" do
    extra = ExtraHour.new
    assert_not extra.valid?
    assert extra.errors[:hours].any?
    assert extra.errors[:performed_on].any?
  end

  test "hours must be greater than zero" do
    extra = extra_hours(:acme_unbilled_with_desc)
    extra.hours = 0
    assert_not extra.valid?
    assert extra.errors[:hours].any?
  end

  test "unbilled scope returns entries without invoice_line_item" do
    unbilled = ExtraHour.unbilled
    assert_includes unbilled, extra_hours(:acme_unbilled_with_desc)
    assert_includes unbilled, extra_hours(:acme_unbilled_generic)
    assert_not_includes unbilled, extra_hours(:acme_billed)
  end

  test "billed? returns true for entries with invoice_line_item" do
    assert extra_hours(:acme_billed).billed?
    assert_not extra_hours(:acme_unbilled_with_desc).billed?
  end

  test "validates line_item_belongs_to_same_client" do
    extra = extra_hours(:acme_unbilled_with_desc)
    extra.invoice_line_item = invoice_line_items(:sakura_january_retainer)
    assert_not extra.valid?
    assert extra.errors[:invoice_line_item].any?
  end

  test "allows line_item from same client" do
    extra = extra_hours(:acme_unbilled_with_desc)
    extra.invoice_line_item = invoice_line_items(:acme_january_retainer)
    assert extra.valid?
  end

  test "cannot modify a billed extra hour" do
    extra = extra_hours(:acme_billed)
    assert extra.billed?
    extra.hours = 5.0
    assert_not extra.valid?
    assert extra.errors[:base].any?
  end

  test "cannot destroy a billed extra hour" do
    extra = extra_hours(:acme_billed)
    assert extra.billed?
    assert_not extra.destroy
    assert extra.errors[:base].any?
  end
end
