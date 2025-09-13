# Only start monitoring jobs when the application is fully running
# Skip during asset precompilation, testing, or when database is not configured
if defined?(Rails) && Rails.application
  Rails.application.config.after_initialize do
    # Multiple checks to ensure we only run when appropriate
    should_skip = Rails.env.test? ||
                  ENV['RAILS_ASSETS_PRECOMPILE'].present? ||
                  ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'].present? ||
                  ENV['SECRET_KEY_BASE_DUMMY'].present? || # Docker build uses this
                  ENV['DATABASE_URL'].blank?
    
    unless should_skip
      begin
        # Double-check database is actually available
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          if connection.active?
            MonitorWaitTimesJob.perform_later
            Rails.logger.info "MonitorWaitTimesJob scheduled successfully"
          end
        end
      rescue => e
        # Database not available or any other error, skip job scheduling
        Rails.logger.warn "Skipping MonitorWaitTimesJob - #{e.class}: #{e.message}"
      end
    end
  end
end