# Rack and Net::HTTP spans record the request path, which can hold a link token
# or a Checkout session id. Their attributes are set when the span starts.
class TokenFilteringSpanProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
  PATH_ATTRIBUTES = %w[ http.target http.url url.full url.path ].freeze

  def on_start(span, _parent_context)
    span.attributes&.slice(*PATH_ATTRIBUTES)&.each do |key, value|
      span.set_attribute key, RequestPathFilter.filter(value) if value.is_a?(String)
    end
  end
end
