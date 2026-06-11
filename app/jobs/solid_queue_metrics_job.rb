# Reports SolidQueue queue-depth gauges to the Prometheus collector accessory.
# Scheduled every minute from config/recurring.yml. Runs in-puma (SOLID_QUEUE_IN_PUMA),
# where PrometheusExporter::Client.default is configured. Metrics are served with the
# collector's "ruby_" prefix, e.g. ruby_solid_queue_pending_jobs.
class SolidQueueMetricsJob < ApplicationJob
  queue_as :default

  GAUGES = {} # name => RemoteMetric, memoized per worker process

  def perform
    report :solid_queue_pending_jobs, "SolidQueue jobs ready to run now", SolidQueue::ReadyExecution.count
    report :solid_queue_scheduled_jobs, "SolidQueue jobs scheduled for the future", SolidQueue::ScheduledExecution.count
    report :solid_queue_failed_jobs, "SolidQueue jobs that have failed", SolidQueue::FailedExecution.count
    report :solid_queue_oldest_pending_age_seconds, "Age in seconds of the oldest job waiting to run", oldest_pending_age
  end

  private
    def oldest_pending_age
      oldest = SolidQueue::ReadyExecution.minimum(:created_at)
      oldest ? (Time.current - oldest).round : 0
    end

    def report(name, help, value)
      gauge = GAUGES[name] ||= PrometheusExporter::Client.default.register(:gauge, name.to_s, help)
      gauge.observe value
    end
end
