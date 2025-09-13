# Skip this entire file during asset precompilation
return if ENV['SECRET_KEY_BASE_DUMMY'].present? || ENV['RAILS_ASSETS_PRECOMPILE'].present?

# Only start monitoring jobs when the application is fully running
Rails.application.config.after_initialize do
  # Skip in test environment or when database URL is not configured
  unless Rails.env.test? || ENV['DATABASE_URL'].blank? || ENV['DISABLE_MONITORING_JOBS'].present?
    begin
      # Ensure database is accessible before scheduling job
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        if connection.active?
          MonitorWaitTimesJob.perform_later
          Rails.logger.info "MonitorWaitTimesJob scheduled successfully"
        end
      end
    rescue => e
      # Database not available, skip job scheduling silently
      Rails.logger.warn "Skipping MonitorWaitTimesJob - #{e.class}: #{e.message}" if Rails.env.development?
    end
  end
end