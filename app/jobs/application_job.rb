class ApplicationJob < ActiveJob::Base
  around_perform do |_job, block|
    if defined?(OpenTelemetry::Trace) && OpenTelemetry::Trace.current_span.context.valid?
      span = OpenTelemetry::Trace.current_span
      SemanticLogger.named_tagged(
        trace_id: span.context.hex_trace_id,
        span_id: span.context.hex_span_id
      ) { block.call }
    else
      block.call
    end
  end
end
