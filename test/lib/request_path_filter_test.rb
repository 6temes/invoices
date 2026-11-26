require "test_helper"

class RequestPathFilterTest < ActiveSupport::TestCase
  test "every route that takes a token is filtered" do
    token_routes = Rails.application.routes.routes.select { it.required_parts.include?(:token) }
    assert_not_empty token_routes

    token_routes.each do |route|
      path = route.format(token: "a-signed--token", format: nil)
      assert_equal path.sub("a-signed--token", "[FILTERED]"), RequestPathFilter.filter(path), route.name
    end
  end

  test "a percent-encoded token or prefix is still filtered" do
    assert_equal "/pay/[FILTERED]", RequestPathFilter.filter("/pay/abc%2D%2Ddef")
    assert_equal "/p%61y/[FILTERED]", RequestPathFilter.filter("/p%61y/abc--def")
  end

  test "Checkout session ids are filtered anywhere in a path, and queries are kept" do
    assert_equal "/v1/checkout/sessions/[FILTERED]?expand=x", RequestPathFilter.filter("/v1/checkout/sessions/cs_test_a1b2?expand=x")
    assert_equal "https://api.stripe.com/v1/checkout/sessions/[FILTERED]", RequestPathFilter.filter("https://api.stripe.com/v1/checkout/sessions/cs_live_a1b2")
  end

  test "paths without a token are unchanged" do
    %w[ /passwords/new /passwords /invoices/12 /pay / ].each do
      assert_equal it, RequestPathFilter.filter(it)
    end
  end
end
