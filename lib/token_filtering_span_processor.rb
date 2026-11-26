# Rack and Net::HTTP spans record the request path, which can hold a link token
# or a Checkout session id. Their attributes are set when the span starts.
class TokenFilteringSpanProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
  PATH_ATTRIBUTES = %w[ http.target http.url url.full url.path ].freeze

  def on_start(span, _parent_context)
    span.attributes&.slice(*PATH_ATTRIBUTES)&.each do |key, value|
      next unless value.is_a?(String)

      # Each write counts towards the span's attribute total, and the exporter
      # reports the excess as dropped attributes.
      filtered = RequestPathFilter.filter(value)
      span.set_attribute key, filtered unless filtered == value
    end
  end
end
