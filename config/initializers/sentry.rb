sentry_dsn = ENV["SENTRY_DSN"].to_s.strip

if sentry_dsn.present?
  traces_sample_rate =
    begin
      Float(ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0"))
    rescue ArgumentError, TypeError
      0.0
    end

  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.enable_logs = true
    config.enabled_patches << :logger unless config.enabled_patches.include?(:logger)
    config.std_lib_logger_filter = lambda do |_logger, _message, severity|
      %i[error fatal].include?(severity)
    end
    config.send_default_pii = false
    config.traces_sample_rate = traces_sample_rate
  end
end
