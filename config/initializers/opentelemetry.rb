# OpenTelemetry tracing — only active when OTEL_EXPORTER_OTLP_ENDPOINT is set.
# Without it, the SDK is never loaded and all OTel API calls are no-ops.
if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present? && !defined?(::Rails::Console)
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"

  OpenTelemetry::SDK.configure do |c|
    c.service_name = "invoices"
    c.service_version = ENV.fetch("GIT_SHA", "unknown")
    c.resource = OpenTelemetry::SDK::Resources::Resource.create(
      "deployment.environment" => Rails.env.to_s
    )
    c.use_all "OpenTelemetry::Instrumentation::Rack" => { untraced_endpoints: [ "/up" ] }
  end

  # Add SQL queries to ActiveRecord OTel spans.
  # The built-in ActiveRecord instrumentation creates timing spans (e.g. "Business query")
  # but doesn't extract SQL from the notification payload, leaving spans empty.
  # This subscriber captures the actual SQL with obfuscated values.
  #
  # We use a SQLite-aware obfuscation regex instead of OpenTelemetry::Helpers::SqlProcessor
  # because its obfuscate_sql method treats double-quoted identifiers ("sessions") as string
  # literals and replaces them with ?, even with adapter: :sqlite (upstream bug — the case
  # statement falls through to DEFAULT_COMPONENTS_REGEX).
  SQLITE_SQL_OBFUSCATION = Regexp.union(
    /'(?:[^']|'')*'/,                          # single-quoted strings
    /-?\b(?:[0-9]+\.)?[0-9]+([eE][+-]?[0-9]+)?\b/, # numeric literals
    /\b(?:true|false|null)\b/i,                # boolean literals
    /0x[0-9a-fA-F]+/,                          # hex literals
    /(?:#|--).*?(?=\r|\n|$)/i,                 # single-line comments
    %r{/\*.*?\*/}m                             # multi-line comments
  )

  ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
    next if payload[:name] == "SCHEMA"
    next if payload[:name] == "CACHE"

    tracer = OpenTelemetry.tracer_provider.tracer("active_record.sql")
    sql = payload[:sql].to_s.gsub(SQLITE_SQL_OBFUSCATION, "?")

    attributes = {
      "db.system.name" => "sqlite",
      "db.query.text" => sql,
      "db.operation.name" => payload[:sql].to_s.split.first&.upcase,
      "db.namespace" => payload[:connection]&.pool&.db_config&.database
    }.compact

    span = tracer.start_span(
      payload[:name] || "SQL",
      attributes: attributes,
      start_timestamp: start
    )
    span.finish(end_timestamp: finish)
  end
end
