require "application_system_test_case"

class BusinessSystemTest < ApplicationSystemTestCase
  setup do
    sign_in
  end

  test "edit page renders all sections" do
    visit edit_business_path
    assert_text "Business Settings"
    assert_field "Name"
    assert_field "Email"
    assert_field "Tax rate (%)"
    assert_field "Registration number"
    # Bank details
    assert_field "Bank"
    assert_field "Branch"
    assert_field "Account number"
    # API tokens section
    assert_text "API Tokens"
    assert_button "Generate token"
  end

  test "generated token opens in a dialog that copies it" do
    visit edit_business_path
    fill_in "Token name", with: "Laptop"
    click_on "Generate token"

    within "dialog[open]" do
      assert_text "Copy it now, it won't be shown again"
      click_on "Copy"
      assert_button "Copied"
      click_on "Done"
    end
    assert_no_selector "dialog[open]"
  end
end
