require "test_helper"

class ClientIpTest < ActionDispatch::IntegrationTest
  VISITOR = "198.51.100.7"
  FORWARDED_CHAIN = "#{VISITOR}, 172.18.0.2"

  test "a Forwarded header does not choose the client IP" do
    get_up "Forwarded" => "for=203.0.113.9", "X-Forwarded-For" => FORWARDED_CHAIN

    assert_client_ip VISITOR
  end

  test "a private Client-IP header does not choose the client IP" do
    get_up "Client-IP" => "10.0.0.1", "X-Forwarded-For" => FORWARDED_CHAIN

    assert_client_ip VISITOR
  end

  test "a Client-IP header missing from X-Forwarded-For does not raise" do
    get_up "Client-IP" => "203.0.113.5", "X-Forwarded-For" => FORWARDED_CHAIN

    assert_client_ip VISITOR
  end

  test "a trusted address prepended to X-Forwarded-For does not win or fall back to Client-IP" do
    get_up "Client-IP" => "203.0.113.5", "X-Forwarded-For" => "127.0.0.1, #{FORWARDED_CHAIN}"

    assert_client_ip VISITOR
  end

  test "Client-IP is the client IP when X-Forwarded-For is absent" do
    get_up "Client-IP" => "203.0.113.5"

    assert_response :success
    assert_equal "203.0.113.5", request.remote_ip
  end

  private
    def get_up(headers)
      get "/up", headers:, env: { "REMOTE_ADDR" => "127.0.0.1" }
    end

    def assert_client_ip(ip)
      assert_response :success
      assert_equal ip, request.remote_ip
      assert_equal ip, request.ip
    end
end
