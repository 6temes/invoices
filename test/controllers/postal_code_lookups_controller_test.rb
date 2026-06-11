require "test_helper"

class PostalCodeLookupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:daniel)
  end

  test "show returns address data for valid postal code" do
    stub_zipcloud_success

    get postal_code_lookup_path, params: { postal_code: "164-0003" }
    assert_response :success
    json = response.parsed_body
    assert_equal "東京都", json["administrative_area"]
    assert_equal "中野区", json["locality"]
    assert_equal "東中野", json["sublocality"]
  end

  test "show returns 422 for invalid postal code format" do
    get postal_code_lookup_path, params: { postal_code: "123" }
    assert_response :unprocessable_entity
  end

  test "show returns 404 when postal code not found" do
    stub_zipcloud({ status: 200, results: nil })

    get postal_code_lookup_path, params: { postal_code: "000-0000" }
    assert_response :not_found
  end

  test "show returns 503 on gateway server error" do
    stub_request(:get, /zipcloud\.ibsnet\.co\.jp\/api\/search/)
      .to_return(status: 500, body: "Internal Server Error")

    get postal_code_lookup_path, params: { postal_code: "164-0003" }
    assert_response :service_unavailable
  end

  test "requires authentication" do
    sign_out
    get postal_code_lookup_path, params: { postal_code: "164-0003" }
    assert_redirected_to new_session_path
  end

  private

  def stub_zipcloud_success
    stub_zipcloud({
      status: 200,
      results: [
        { address1: "東京都", address2: "中野区", address3: "東中野" }
      ]
    })
  end

  def stub_zipcloud(body)
    stub_request(:get, /zipcloud\.ibsnet\.co\.jp\/api\/search/)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: body.to_json
      )
  end
end
