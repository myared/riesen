ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all  # Disabled to avoid conflicts with dynamic test data

    # Add more helper methods to be used by all tests here...

    # Helper method to ensure ApplicationSetting exists with known values for tests
    def ensure_application_setting
      ApplicationSetting.destroy_all
      ApplicationSetting.create!(
        ed_rooms: 20,
        rp_rooms: 12,
        esi_1_target: 0,
        esi_2_target: 10,
        esi_3_target: 30,
        esi_4_target: 60,
        esi_5_target: 120,
        medicine_ordered_target: 30,
        medicine_administered_target: 60,
        lab_ordered_target: 15,
        lab_collected_target: 30,
        lab_in_lab_target: 45,
        lab_resulted_target: 60,
        imaging_ordered_target: 20,
        imaging_exam_started_target: 40,
        imaging_exam_completed_target: 60,
        imaging_resulted_target: 80,
        warning_threshold_percentage: 75,
        critical_threshold_percentage: 100
      )
    end
  end
end
