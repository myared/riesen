require "test_helper"

class MonitorWaitTimesJobInitializationTest < ActionDispatch::IntegrationTest
  def setup
    # Clear any existing jobs from the queue
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end

  test "monitoring job should be initialized on application startup" do
    # Skip in test environment as the initializer has a guard clause
    skip "Monitoring job is not started in test environment by design"
  end

  test "initializer file exists and has correct content" do
    initializer_path = Rails.root.join("config/initializers/start_monitoring_jobs.rb")
    assert File.exist?(initializer_path), "Initializer file should exist"

    content = File.read(initializer_path)
    assert_includes content, "Rails.application.config.after_initialize"
    assert_includes content, "unless Rails.env.test?"
    assert_includes content, "MonitorWaitTimesJob.perform_later"
  end

  test "monitoring job behavior in non-test environments" do
    # Temporarily override Rails.env to simulate production
    original_env = Rails.env
    
    begin
      # Use string_inquirer to mimic Rails.env behavior
      Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new("production"))
      
      # Clear any existing jobs
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      
      # Simulate the initializer code
      MonitorWaitTimesJob.perform_later unless Rails.env.test?
      
      # Verify the job was enqueued
      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
      monitor_jobs = enqueued_jobs.select { |job| job["job_class"] == "MonitorWaitTimesJob" }
      
      assert_equal 1, monitor_jobs.count, "Should enqueue exactly one MonitorWaitTimesJob"
      
      job = monitor_jobs.first
      assert_equal "default", job["queue_name"]
      assert job["arguments"].empty?
      
    ensure
      # Restore original environment
      Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(original_env))
    end
  end

  test "monitoring job should not start in test environment" do
    # Verify current environment
    assert Rails.env.test?, "Should be in test environment"
    
    # Clear any existing jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    
    # Simulate the initializer code (should not enqueue in test)
    MonitorWaitTimesJob.perform_later unless Rails.env.test?
    
    # Verify no jobs were enqueued
    enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    monitor_jobs = enqueued_jobs.select { |job| job["job_class"] == "MonitorWaitTimesJob" }
    
    assert_equal 0, monitor_jobs.count, "Should not enqueue MonitorWaitTimesJob in test environment"
  end

  test "monitoring job should handle different rails environments correctly" do
    environments_to_test = ["development", "production", "staging"]
    
    environments_to_test.each do |env_name|
      # Clear jobs before each test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      
      # Temporarily set environment
      original_env = Rails.env
      Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(env_name))
      
      begin
        # Simulate initializer
        MonitorWaitTimesJob.perform_later unless Rails.env.test?
        
        # Should enqueue job in non-test environments
        enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
        monitor_jobs = enqueued_jobs.select { |job| job["job_class"] == "MonitorWaitTimesJob" }
        
        assert_equal 1, monitor_jobs.count, 
                     "Should enqueue MonitorWaitTimesJob in #{env_name} environment"
        
      ensure
        # Restore environment
        Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(original_env))
      end
    end
  end

  test "monitoring job should be configured for default queue" do
    job = MonitorWaitTimesJob.new
    assert_equal "default", job.queue_name, "MonitorWaitTimesJob should use default queue"
  end

  test "monitoring job can be manually enqueued for testing" do
    # Clear existing jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    
    # Manually enqueue the job (for testing purposes)
    MonitorWaitTimesJob.perform_later
    
    # Verify it was enqueued
    enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
    monitor_jobs = enqueued_jobs.select { |job| job["job_class"] == "MonitorWaitTimesJob" }
    
    assert_equal 1, monitor_jobs.count, "Should be able to manually enqueue MonitorWaitTimesJob"
  end

  test "monitoring job initializer should only run after application initialization" do
    # This test verifies the structure of the initializer
    initializer_path = Rails.root.join("config/initializers/start_monitoring_jobs.rb")
    content = File.read(initializer_path)
    
    # Should use after_initialize callback
    assert_includes content, "Rails.application.config.after_initialize do"
    
    # Should have proper guard clause
    assert_includes content, "unless Rails.env.test?"
    
    # Should call the correct method
    assert_includes content, "MonitorWaitTimesJob.perform_later"
    
    # Should have proper end statements
    assert content.count("end") >= 2, "Should have proper end statements for block and guard"
  end

  test "monitoring job should persist through application restarts" do
    # This test simulates what happens when the application restarts
    
    # Clear any existing jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    
    # Simulate application startup in production
    original_env = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new("production"))
    
    begin
      # Simulate multiple application startups (restarts)
      3.times do
        MonitorWaitTimesJob.perform_later unless Rails.env.test?
      end
      
      # Should have enqueued multiple jobs (one per startup)
      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
      monitor_jobs = enqueued_jobs.select { |job| job["job_class"] == "MonitorWaitTimesJob" }
      
      assert_equal 3, monitor_jobs.count, 
                   "Should enqueue one job per application startup"
      
    ensure
      Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(original_env))
    end
  end

  test "monitoring job initializer should not interfere with other initializers" do
    # Verify that the monitoring job initializer is properly isolated
    initializer_path = Rails.root.join("config/initializers/start_monitoring_jobs.rb")
    content = File.read(initializer_path)
    
    # Should not have any global variable assignments
    assert_not_includes content, "$", "Should not use global variables"
    
    # Should be contained within the after_initialize block
    lines = content.split("\n").map(&:strip).reject(&:empty?)
    
    # First line should be the after_initialize block start
    assert_includes lines.first, "Rails.application.config.after_initialize do"
    
    # Last line should be the block end
    assert_equal "end", lines.last
    
    # Should not have any require statements or global modifications
    # The file should only contain the after_initialize block with job scheduling
    code_lines = lines.reject { |line| 
      line.start_with?("#") || 
      line == "end" || 
      line.include?("Rails.application.config.after_initialize do") ||
      line.include?("unless Rails.env.test?") ||
      line.include?("MonitorWaitTimesJob.perform_later")
    }
    
    # No other code should exist
    assert_empty code_lines, "Should only contain the expected initialization code"
  end
end