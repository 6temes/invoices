require "test_helper"

class InvoicesHelperTest < ActionView::TestCase
  test "item_type_label localizes known types per invoice locale" do
    assert_equal "Service", item_type_label("Service")

    I18n.with_locale(:ja) do
      assert_equal "サービス", item_type_label("Service")
    end
  end

  test "item_type_label falls back to the raw value for unknown types" do
    I18n.with_locale(:ja) do
      assert_equal "Consulting", item_type_label("Consulting")
    end
  end
end
