require "test_helper"
require "prometheus_exporter/client" # not loaded in test env (see initializer), needed to stub the client

class SolidQueueMetricsJobTest < ActiveSupport::TestCase
  test "reports queue-depth gauges to the prometheus collector" do
    SolidQueueMetricsJob::GAUGES.clear
    SolidQueue::ReadyExecution.stubs(count: 7, minimum: 3.minutes.ago)
    SolidQueue::ScheduledExecution.stubs(count: 2)
    SolidQueue::FailedExecution.stubs(count: 1)

    # perform reports pending, scheduled, failed, oldest-age in that order
    pending_gauge = mock
    pending_gauge.expects(:observe).with(7)
    age_gauge = mock
    age_gauge.expects(:observe).with { |seconds| seconds.between?(175, 185) } # ~3 minutes
    scheduled_gauge = mock.tap { _1.expects(:observe).with(2) }
    failed_gauge = mock.tap { _1.expects(:observe).with(1) }

    client = mock
    client.stubs(:register).returns(pending_gauge, scheduled_gauge, failed_gauge, age_gauge)
    PrometheusExporter::Client.stubs(:default).returns(client)

    SolidQueueMetricsJob.new.perform
  end
end
