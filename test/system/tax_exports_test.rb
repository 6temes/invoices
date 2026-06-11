require "application_system_test_case"

class TaxExportsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in
  end

  test "show page renders year selector and summary cards" do
    visit tax_export_path
    assert_text "Tax Export"
    assert_selector "select[name=year]"
    assert_selector ".summary-card", minimum: 3
    assert_text "Per-Client Breakdown"
    assert_link "Download CSV"
    assert_link "Download ZIP (PDFs + UBL XML)"
  end
end
