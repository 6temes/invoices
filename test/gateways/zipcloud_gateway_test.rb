require "test_helper"

class ZipcloudGatewayTest < ActiveSupport::TestCase
  test "lookup returns address components for valid postal code" do
    stub_zipcloud success_body

    result = ZipcloudGateway.lookup("150-0001")
    assert_equal "東京都", result[:administrative_area]
    assert_equal "渋谷区", result[:locality]
    assert_equal "神宮前", result[:sublocality]
  end

  test "lookup raises NotFoundError when no results" do
    stub_zipcloud({ status: 200, results: nil })

    assert_raises(ZipcloudGateway::NotFoundError) do
      ZipcloudGateway.lookup("000-0000")
    end
  end

  test "lookup raises ServerError on HTTP failure" do
    stub_request(:get, /zipcloud\.ibsnet\.co\.jp\/api\/search/)
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(ZipcloudGateway::ServerError) do
      ZipcloudGateway.lookup("150-0001")
    end
  end

  test "lookup raises ServerError on API error status" do
    stub_zipcloud({ status: 400, message: "Bad request" })

    assert_raises(ZipcloudGateway::ServerError) do
      ZipcloudGateway.lookup("150-0001")
    end
  end

  private

  def success_body
    {
      status: 200,
      results: [
        { address1: "東京都", address2: "渋谷区", address3: "神宮前" }
      ]
    }
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
