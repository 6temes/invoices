Rails.application.config.after_initialize do
  next if Rails.env.test?

  Rails.logger.info(
    event: "deploy",
    version: ENV.fetch("GIT_SHA", "unknown"),
    started_at: Time.current.iso8601
  )
end
