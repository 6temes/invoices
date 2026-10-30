require "mcp/server/transports/streamable_http_transport"

# The gem passes (exception, context) and its context holds the ApiToken, so only the exception is reported.
MCP.configuration.exception_reporter = ->(exception, _context) { Rails.error.report(exception, source: "mcp") }
