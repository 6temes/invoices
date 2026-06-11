class TraceparentHeaderMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    if defined?(OpenTelemetry::Trace)
      span = OpenTelemetry::Trace.current_span
      if span.context.valid?
        sampled = span.context.trace_flags.sampled? ? "01" : "00"
        headers["traceparent"] = "00-#{span.context.hex_trace_id}-#{span.context.hex_span_id}-#{sampled}"
      end
    end

    [ status, headers, response ]
  end
end
