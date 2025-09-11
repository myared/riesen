Rails.application.config.after_initialize do
  unless Rails.env.test?
    MonitorWaitTimesJob.perform_later
  end
end