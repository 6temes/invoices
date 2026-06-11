require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/middleware/traceparent_header_middleware"

module Invoices
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets middleware tasks])
    config.time_zone = "Tokyo"

    config.middleware.use TraceparentHeaderMiddleware

    # SemanticLogger: structured JSON logging to stdout, no file appender
    config.rails_semantic_logger.add_file_appender = false
    config.rails_semantic_logger.quiet_assets = true
    config.semantic_logger.add_appender io: $stdout, formatter: :json

    # Inject request_id and OTel trace context into all log lines
    config.log_tags = {
      request_id: :request_id,
      trace_id: ->(_request) { OpenTelemetry::Trace.current_span.context.hex_trace_id if defined?(OpenTelemetry::Trace) && OpenTelemetry::Trace.current_span.context.valid? },
      span_id: ->(_request) { OpenTelemetry::Trace.current_span.context.hex_span_id if defined?(OpenTelemetry::Trace) && OpenTelemetry::Trace.current_span.context.valid? }
    }
  end
end
