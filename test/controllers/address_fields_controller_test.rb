require "test_helper"

class AddressFieldsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "show renders JP fields partial" do
    get address_fields_path, params: { country_code: "JP", object_name: "client[address_attributes]" }
    assert_response :success
    assert_match "Postal code", response.body
  end

  test "show renders ES fields partial" do
    get address_fields_path, params: { country_code: "ES", object_name: "client[address_attributes]" }
    assert_response :success
    assert_match "Código postal", response.body
  end

  test "show renders generic fields partial" do
    get address_fields_path, params: { country_code: "US", object_name: "client[address_attributes]" }
    assert_response :success
    assert_match "Address line 1", response.body
  end

  test "show defaults to JP when no country_code" do
    get address_fields_path, params: { object_name: "client[address_attributes]" }
    assert_response :success
    assert_match "Postal code", response.body
  end

  test "show returns bad request for invalid object_name" do
    get address_fields_path, params: { country_code: "JP", object_name: "hacked[params]" }
    assert_response :bad_request
  end

  test "show accepts business object_name" do
    get address_fields_path, params: { country_code: "JP", object_name: "business[address_attributes]" }
    assert_response :success
  end

  test "show returns bad request for invalid country_code format" do
    get address_fields_path, params: { country_code: "../../etc", object_name: "client[address_attributes]" }
    assert_response :bad_request
  end

  test "requires authentication" do
    sign_out
    get address_fields_path, params: { country_code: "JP", object_name: "client[address_attributes]" }
    assert_redirected_to new_session_path
  end
end
