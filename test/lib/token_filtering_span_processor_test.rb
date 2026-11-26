require "test_helper"

class TokenFilteringSpanProcessorTest < ActiveSupport::TestCase
  setup do
    @exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    @provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    @provider.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@exporter)
    @provider.add_span_processor TokenFilteringSpanProcessor.new
  end

  test "server spans keep the route but not the link token" do
    finish_span "/pay/abc%2D%2Ddef", "url.path" => "/pay/abc%2D%2Ddef", "http.target" => "/pay/abc%2D%2Ddef?locale=ja", "http.route" => "/pay/:token"

    attributes = @exporter.finished_spans.sole.attributes
    assert_equal "/pay/[FILTERED]", attributes["url.path"]
    assert_equal "/pay/[FILTERED]?locale=ja", attributes["http.target"]
    assert_equal "/pay/:token", attributes["http.route"]
  end

  test "client spans leave out a Checkout session id" do
    finish_span "GET", "url.full" => "https://api.stripe.com/v1/checkout/sessions/cs_test_a1b2", "url.path" => "/v1/checkout/sessions/cs_test_a1b2"

    attributes = @exporter.finished_spans.sole.attributes
    assert_not_includes attributes.values.join(" "), "cs_test_a1b2"
  end

  test "a path without a token is left as recorded" do
    finish_span "GET /invoices/1", "url.path" => "/invoices/1"

    span = @exporter.finished_spans.sole
    assert_equal "/invoices/1", span.attributes["url.path"]
    assert_equal 1, span.total_recorded_attributes
  end

  test "an app booted with an OTLP endpoint filters spans and still exports them" do
    script = "print OpenTelemetry.tracer_provider.instance_variable_get(:@span_processors).map { it.class.name }.join(',')"
    output, status = Open3.capture2({ "OTEL_EXPORTER_OTLP_ENDPOINT" => "http://127.0.0.1:9", "RAILS_ENV" => "test" },
      Rails.root.join("bin/rails").to_s, "runner", script, err: File::NULL)

    assert status.success?
    assert_includes output, "TokenFilteringSpanProcessor"
    assert_includes output, "OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor"
  end

  private

  def finish_span(name, attributes)
    @provider.tracer("test").start_span(name, attributes:).finish
  end
end
