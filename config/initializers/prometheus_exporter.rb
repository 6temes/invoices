unless Rails.env.test?
  require "prometheus_exporter/client"
  require "prometheus_exporter/instrumentation"
  require "prometheus_exporter/middleware"

  # Metrics collector runs as a separate Kamal accessory (invoices-prometheus-exporter)
  # to avoid port conflicts during zero-downtime deploys
  PrometheusExporter::Client.default = PrometheusExporter::Client.new(
    host: ENV.fetch("PROMETHEUS_COLLECTOR_HOST", "localhost"),
    port: 9394
  )

  # Skip health checks and assets — they skew response time and throughput metrics
  class FilteredPrometheusMiddleware < PrometheusExporter::Middleware
    SKIP_PATHS = %w[/up /assets].freeze

    def call(env)
      if SKIP_PATHS.any? { env["PATH_INFO"].start_with? _1 }
        @app.call(env)
      else
        super
      end
    end
  end

  Rails.application.middleware.unshift FilteredPrometheusMiddleware
end
