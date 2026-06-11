require "test_helper"

class BusinessesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "edit renders business settings" do
    get edit_business_path
    assert_response :success
  end

  test "update changes business attributes" do
    patch business_path, params: {
      business: {
        name: "Updated Name",
        tax_registration_number: businesses(:default).tax_registration_number,
        bank_name: businesses(:default).bank_name,
        bank_branch: businesses(:default).bank_branch,
        bank_account_holder: businesses(:default).bank_account_holder,
        bank_account_type: businesses(:default).bank_account_type,
        bank_account_number: businesses(:default).bank_account_number,
        email: businesses(:default).email,
        tax_rate: 10,
        next_invoice_number: 150,
        address_attributes: {
          id: addresses(:business_address).id,
          country_code: "JP",
          postal_code: "164-0003",
          administrative_area: "東京都",
          locality: "中野区",
          sublocality: "東中野",
          street: "1-17-7 Updated"
        }
      }
    }
    assert_redirected_to edit_business_path
    assert_equal "Updated Name", businesses(:default).reload.name
  end

  test "update with invalid params renders edit" do
    patch business_path, params: { business: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    sign_out
    get edit_business_path
    assert_redirected_to new_session_path
  end
end
