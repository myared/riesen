Rails.application.config.after_initialize do
  # Skip during asset precompilation, test environment, or when explicitly disabled
  if !Rails.env.test? && !ENV['RAILS_ASSETS_PRECOMPILE'] && !ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK']
    begin
      # Only start monitoring job if database is accessible
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        if connection.active?
          MonitorWaitTimesJob.perform_later
          Rails.logger.info "MonitorWaitTimesJob scheduled successfully"
        end
      end
    rescue => e
      # Database not available or any other error, skip job scheduling
      Rails.logger.info "Skipping MonitorWaitTimesJob - #{e.class}: #{e.message}"
    end
  end
end