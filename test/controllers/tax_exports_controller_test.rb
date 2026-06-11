require "test_helper"

class TaxExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "show renders tax export page" do
    get tax_export_path
    assert_response :success
  end

  test "show with year parameter" do
    get tax_export_path(year: 2025)
    assert_response :success
  end

  test "csv downloads CSV file" do
    get csv_tax_export_path(year: 2025)
    assert_response :success
    assert_equal "text/csv", response.media_type
  end

  test "zip downloads ZIP file" do
    get zip_tax_export_path(year: 2025)
    assert_response :success
    assert_equal "application/zip", response.media_type
  end

  test "csv contains correct headers and invoice data" do
    get csv_tax_export_path(year: 2025)
    assert_response :success

    lines = response.body.lines
    headers = lines.first.strip.split(",")
    assert_includes headers, "invoice_number"
    assert_includes headers, "client_name"
    assert_includes headers, "total"
    assert_includes headers, "status"
  end

  test "requires authentication" do
    sign_out
    get tax_export_path
    assert_redirected_to new_session_path
  end
end
