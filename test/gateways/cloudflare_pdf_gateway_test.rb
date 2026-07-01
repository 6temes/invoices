require "test_helper"

class CloudflarePdfGatewayTest < ActiveSupport::TestCase
  setup do
    @endpoint = %r{api\.cloudflare\.com/client/v4/accounts/.*/browser-rendering/pdf}
  end

  test "render returns PDF binary on success" do
    stub_request(:post, @endpoint)
      .to_return(status: 200, body: "%PDF-1.4 fake", headers: { "Content-Type" => "application/pdf" })

    result = CloudflarePdfGateway.render "<h1>Invoice</h1>"
    assert_equal "%PDF-1.4 fake", result
  end

  test "render raises ServerError on 5xx" do
    stub_request(:post, @endpoint)
      .to_return(status: 502, body: "Bad Gateway")

    assert_raises CloudflarePdfGateway::ServerError do
      CloudflarePdfGateway.render "<h1>Invoice</h1>"
    end
  end

  test "render raises ClientError on 4xx" do
    stub_request(:post, @endpoint)
      .to_return(status: 400, body: "Bad Request")

    assert_raises CloudflarePdfGateway::ClientError do
      CloudflarePdfGateway.render "<h1>Invoice</h1>"
    end
  end

  test "render raises RateLimitError on 429" do
    stub_request(:post, @endpoint)
      .to_return(status: 429, body: "Too Many Requests")

    assert_raises CloudflarePdfGateway::RateLimitError do
      CloudflarePdfGateway.render "<h1>Invoice</h1>"
    end
  end
end
