# Payment, credit and password-reset links carry a signed token as the segment
# after their prefix, and Stripe API paths carry Checkout session ids. This
# removes both from a path or URL before it reaches traces or error capture.
module RequestPathFilter
  FILTERED = "[FILTERED]"
  TOKEN_PREFIXES = %w[ pay credit passwords ].freeze
  # Segments that follow a prefix without being a token, like /passwords/new.
  ROUTE_WORDS = %w[ new ].freeze
  CHECKOUT_SESSION_ID = /\Acs_(?:test|live)_/

  def self.filter(path_or_url)
    location, separator, query = path_or_url.partition("?")
    previous = nil
    segments = location.split("/", -1).map do |segment|
      # A scanner's %FF is not UTF-8, and matching it unscrubbed raises.
      decoded = CGI.unescapeURIComponent(segment).scrub
      token = decoded.match?(CHECKOUT_SESSION_ID) || (previous.in?(TOKEN_PREFIXES) && !decoded.in?(ROUTE_WORDS) && decoded.present?)
      # The router ignores empty segments, so /pay//token still reaches the token.
      previous = decoded if decoded.present?
      token ? FILTERED : segment
    end
    "#{segments.join("/")}#{separator}#{query}"
  end
end
