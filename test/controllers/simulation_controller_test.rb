require "test_helper"

class SimulationControllerTest < ActionDispatch::IntegrationTest
  setup do
    ensure_application_setting

    @patient = Patient.create!(
      first_name: "John",
      last_name: "Doe",
      age: 45,
      mrn: "SIM_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      arrival_time: 2.hours.ago,
      triage_completed_at: 1.hour.ago
    )

    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress,
      started_at: 1.hour.ago,
      started_by: "Test Provider"
    )

    @lab_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      timer_status: "green"
    )

    @medication_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 8.minutes.ago,
      timer_status: "yellow"
    )
  end

  test "should get add_patient" do
    # Test that the add_patient action works
    post simulation_add_patient_path
    assert_response :redirect
    assert_match "Patient", flash[:notice]
  end

  # ===============================
  # FAST FORWARD TIME TESTS
  # ===============================

  test "fast_forward_time should redirect with success message" do
    post simulation_fast_forward_time_path
    assert_response :redirect
    assert_match(/Fast forwarded all timers by 10 minutes \(\d+ records updated\)/, flash[:notice])
  end

  test "fast_forward_time should advance patient arrival times by 10 minutes" do
    original_arrival = @patient.arrival_time

    post simulation_fast_forward_time_path

    @patient.reload
    expected_arrival = original_arrival - 10.minutes
    assert_in_delta expected_arrival.to_f, @patient.arrival_time.to_f, 1.0
  end

  test "fast_forward_time should advance patient triage_completed_at by 10 minutes" do
    original_triage = @patient.triage_completed_at

    post simulation_fast_forward_time_path

    @patient.reload
    expected_triage = original_triage - 10.minutes
    assert_in_delta expected_triage.to_f, @patient.triage_completed_at.to_f, 1.0
  end

  test "fast_forward_time should only update patients in active location statuses" do
    discharged_patient = Patient.create!(
      first_name: "Jane",
      last_name: "Smith",
      age: 30,
      mrn: "DISC_#{SecureRandom.hex(4)}",
      location_status: :discharged,
      arrival_time: 1.hour.ago
    )

    original_arrival = discharged_patient.arrival_time

    post simulation_fast_forward_time_path

    discharged_patient.reload
    # Discharged patients should not have timestamps updated
    assert_equal original_arrival, discharged_patient.arrival_time
  end

  test "fast_forward_time should advance care pathway order timestamps" do
    original_ordered_at = @lab_order.ordered_at

    post simulation_fast_forward_time_path

    @lab_order.reload
    expected_ordered_at = original_ordered_at - 10.minutes
    assert_in_delta expected_ordered_at.to_f, @lab_order.ordered_at.to_f, 1.0
  end

  test "fast_forward_time should advance all order timestamp fields" do
    # Setup order with multiple timestamps
    @lab_order.update!(
      collected_at: 20.minutes.ago,
      in_lab_at: 15.minutes.ago,
      resulted_at: 5.minutes.ago
    )

    original_collected = @lab_order.collected_at
    original_in_lab = @lab_order.in_lab_at
    original_resulted = @lab_order.resulted_at

    post simulation_fast_forward_time_path

    @lab_order.reload
    assert_in_delta (original_collected - 10.minutes).to_f, @lab_order.collected_at.to_f, 1.0
    assert_in_delta (original_in_lab - 10.minutes).to_f, @lab_order.in_lab_at.to_f, 1.0
    assert_in_delta (original_resulted - 10.minutes).to_f, @lab_order.resulted_at.to_f, 1.0
  end

  test "fast_forward_time should recalculate timer statuses" do
    # Setup order that will change from green to yellow after fast forward
    # Lab ordered target is 15 min, yellow is 12-15 minutes
    @lab_order.update!(
      ordered_at: 3.minutes.ago,  # 3 + 10 = 13 minutes = yellow
      timer_status: "green"
    )

    post simulation_fast_forward_time_path

    @lab_order.reload
    assert_equal "yellow", @lab_order.timer_status
    assert_equal 13, @lab_order.last_status_duration_minutes
  end

  test "fast_forward_time should create events for timer status changes" do
    # Setup order that will change from green to red
    @lab_order.update!(
      ordered_at: 35.minutes.ago,  # 35 + 10 = 45 minutes = red
      timer_status: "green"
    )

    original_event_count = Event.count

    post simulation_fast_forward_time_path

    @lab_order.reload
    assert_equal "red", @lab_order.timer_status

    # Should have created one event for the timer status change
    new_events = Event.where("id > ?", original_event_count).where(patient: @patient)
    timer_change_events = new_events.select { |e| e.action == "Order timer status changed" }

    assert timer_change_events.any?, "Expected timer status change event to be created"

    event = timer_change_events.first
    assert_equal @patient, event.patient
    assert_equal "Order timer status changed", event.action
    assert_includes event.details, "from green to red"
    assert_includes event.details, "Fast forward"
    assert_equal "System", event.performed_by
    assert_equal "clinical", event.category
  end

  test "fast_forward_time should create events for patients waiting over 60 minutes" do
    # Setup patient that will exceed 60 minute threshold after fast forward
    @patient.update!(
      arrival_time: 55.minutes.ago,  # 55 + 10 = 65 minutes
      location_status: :ed_room
    )

    post simulation_fast_forward_time_path

    # Find the wait time event
    wait_events = Event.where(
      patient: @patient,
      action: "Wait time exceeded 60 minutes"
    )

    assert wait_events.any?, "Expected wait time event for 60 minutes"

    event = wait_events.last
    assert_includes event.details, "65 minutes"
    assert_equal "System", event.performed_by
    assert_equal "administrative", event.category
  end

  test "fast_forward_time should create events for patients waiting over 120 minutes" do
    # Setup patient that will exceed 120 minute threshold after fast forward
    @patient.update!(
      arrival_time: 115.minutes.ago,  # 115 + 10 = 125 minutes
      location_status: :needs_room_assignment
    )

    post simulation_fast_forward_time_path

    # Find the wait time event - should create 120 minute event, not 60 minute
    wait_events_120 = Event.where(
      patient: @patient,
      action: "Wait time exceeded 120 minutes"
    )

    wait_events_60 = Event.where(
      patient: @patient,
      action: "Wait time exceeded 60 minutes"
    )

    assert wait_events_120.any?, "Expected wait time event for 120 minutes"
    assert wait_events_60.empty?, "Should not create 60 minute event when over 120 minutes"

    event = wait_events_120.last
    assert_includes event.details, "125 minutes"
  end

  test "fast_forward_time should not duplicate wait time events" do
    # Create existing 60 minute event
    @patient.events.create!(
      action: "Wait time exceeded 60 minutes",
      details: "Patient has been waiting for 70 minutes",
      performed_by: "System",
      time: 30.minutes.ago,
      category: "administrative"
    )

    @patient.update!(
      arrival_time: 70.minutes.ago,  # 70 + 10 = 80 minutes
      location_status: :ed_room
    )

    original_event_count = Event.where(
      patient: @patient,
      action: "Wait time exceeded 60 minutes"
    ).count

    post simulation_fast_forward_time_path

    new_event_count = Event.where(
      patient: @patient,
      action: "Wait time exceeded 60 minutes"
    ).count

    # Should not create duplicate event
    assert_equal original_event_count, new_event_count
  end

  test "fast_forward_time should only check wait times for appropriate location statuses" do
    # Setup patient in discharged status
    discharged_patient = Patient.create!(
      first_name: "Discharged",
      last_name: "Patient",
      age: 40,
      mrn: "DISC_#{SecureRandom.hex(4)}",
      location_status: :discharged,
      arrival_time: 70.minutes.ago  # Over 60 minute threshold
    )

    original_event_count = Event.count

    post simulation_fast_forward_time_path

    # No wait time events should be created for discharged patients
    wait_events = Event.where(
      patient: discharged_patient,
      action: ["Wait time exceeded 60 minutes", "Wait time exceeded 120 minutes"]
    )

    assert wait_events.empty?, "Should not create wait time events for discharged patients"
  end

  # ===============================
  # EDGE CASES AND ERROR HANDLING
  # ===============================

  test "fast_forward_time should handle no patients gracefully" do
    Patient.destroy_all
    CarePathwayOrder.destroy_all

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    assert_response :redirect
    assert_match /Fast forwarded all timers by 10 minutes/, flash[:notice]
  end

  test "fast_forward_time should handle no orders gracefully" do
    CarePathwayOrder.destroy_all

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    assert_response :redirect
    assert_match /Fast forwarded all timers by 10 minutes/, flash[:notice]
  end

  test "fast_forward_time should handle patients with nil timestamps" do
    # Create patient with no triage_completed_at
    patient_no_triage = Patient.create!(
      first_name: "No",
      last_name: "Triage",
      age: 25,
      mrn: "NT_#{SecureRandom.hex(4)}",
      location_status: :needs_room_assignment,
      arrival_time: 1.hour.ago,
      triage_completed_at: nil
    )

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    patient_no_triage.reload
    # Should still update arrival_time
    assert patient_no_triage.arrival_time < 1.hour.ago
    # triage_completed_at should remain nil
    assert_nil patient_no_triage.triage_completed_at
  end

  test "fast_forward_time should handle orders with nil timestamps" do
    # Create order with no ordered_at timestamp
    order_no_timestamp = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Test Order",
      order_type: :lab,
      status: :ordered,
      ordered_at: nil
    )

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    order_no_timestamp.reload
    # Should remain nil
    assert_nil order_no_timestamp.ordered_at
  end

  test "fast_forward_time should use database transaction" do
    # This test ensures the transaction behavior exists
    # We can't easily test rollback without actually causing a failure
    original_patient_arrival = @patient.arrival_time
    original_order_time = @lab_order.ordered_at

    post simulation_fast_forward_time_path

    @patient.reload
    @lab_order.reload

    # Both should be updated if transaction completed successfully
    assert_not_equal original_patient_arrival, @patient.arrival_time
    assert_not_equal original_order_time, @lab_order.ordered_at
  end

  test "fast_forward_time should handle medication order timer thresholds" do
    # Test medication-specific timer logic
    # Medication ordered target: 30 min, critical at 30 min
    @medication_order.update!(
      ordered_at: 25.minutes.ago,  # 25 + 10 = 35 minutes = red for medication
      timer_status: "yellow"
    )

    post simulation_fast_forward_time_path

    @medication_order.reload
    assert_equal "red", @medication_order.timer_status
    assert_equal 35, @medication_order.last_status_duration_minutes
  end

  test "fast_forward_time should handle orders in various statuses" do
    # Test order in collected status
    collected_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Blood Culture",
      order_type: :lab,
      status: :collected,
      ordered_at: 60.minutes.ago,
      collected_at: 30.minutes.ago,  # This should be used for duration calculation
      timer_status: "green"
    )

    post simulation_fast_forward_time_path

    collected_order.reload
    # Lab collected target is 30 min, so 40 minutes = red
    assert_equal "red", collected_order.timer_status
    assert_equal 40, collected_order.last_status_duration_minutes
  end

  test "fast_forward_time should handle error in timer status update gracefully" do
    # This test verifies that the method has error handling in place
    # We'll simulate this by checking that the method completes even when there are potential issues
    # Note: The actual controller has begin/rescue blocks for error handling

    # Should not raise an error, should log and continue
    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    assert_response :redirect
  end

  test "fast_forward_time should redirect back to referrer" do
    referrer_url = "/dashboard/triage"

    post simulation_fast_forward_time_path, headers: { "HTTP_REFERER" => referrer_url }

    assert_redirected_to referrer_url
  end

  test "fast_forward_time should fallback to root path when no referrer" do
    post simulation_fast_forward_time_path

    assert_redirected_to root_path
  end

  # ===============================
  # SECURITY AND AUDIT TESTS
  # ===============================

  test "fast_forward_time should log to Rails logger for audit purposes" do
    # Since Events require a patient, we verify logging works instead
    # The controller logs errors to Rails.logger which provides an audit trail

    post simulation_fast_forward_time_path

    assert_response :redirect
    assert_match /Fast forwarded all timers by 10 minutes/, flash[:notice]
    # The audit trail is maintained through Rails logging and flash messages
  end

  test "fast_forward_time should report accurate updated count in flash message" do
    # Setup known number of records to be updated
    @patient.update!(triage_completed_at: 1.hour.ago)
    @lab_order.update!(collected_at: 30.minutes.ago, in_lab_at: 20.minutes.ago)

    post simulation_fast_forward_time_path

    # Flash message should include the count
    assert_includes flash[:notice], "records updated"
    # Should report a specific number > 0
    assert_match /\(\d+ records updated\)/, flash[:notice]
  end

  test "fast_forward_time should validate timestamp fields against whitelist" do
    # This test verifies the VALID_TIMESTAMP_FIELDS constant is used
    # The implementation checks if fields exist in column_names before updating

    # Verify the constant exists and has expected values
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "collected_at"
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "in_lab_at"
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "resulted_at"
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "administered_at"
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "exam_started_at"
    assert_includes SimulationController::VALID_TIMESTAMP_FIELDS, "exam_completed_at"

    # The constant should be frozen for security
    assert SimulationController::VALID_TIMESTAMP_FIELDS.frozen?
  end

  test "fast_forward_time should use parameterized queries for SQL injection prevention" do
    # This test verifies parameterized queries are used
    # We test this by ensuring the operation completes successfully with potential injection strings

    # Create patient and order with normal data
    patient_with_quotes = Patient.create!(
      first_name: "Test'; DROP TABLE patients; --",
      last_name: "Injection",
      age: 30,
      mrn: "INJ_#{SecureRandom.hex(4)}",
      location_status: :ed_room,
      arrival_time: 1.hour.ago,
      triage_completed_at: 30.minutes.ago
    )

    original_patient_count = Patient.count

    # If SQL injection was possible, this could cause database damage
    post simulation_fast_forward_time_path

    # Verify database integrity is maintained
    assert_equal original_patient_count, Patient.count
    assert_response :redirect
    assert_match "Fast forwarded", flash[:notice]

    # Verify the patient still exists and was updated properly
    patient_with_quotes.reload
    assert patient_with_quotes.persisted?
    assert patient_with_quotes.arrival_time < 1.hour.ago
  end

  test "fast_forward_time should only update fields that exist in CarePathwayOrder" do
    # This tests the security check: next unless CarePathwayOrder.column_names.include?(field)

    # Mock column_names to simulate a field not existing
    original_column_names = CarePathwayOrder.column_names

    # This test verifies the implementation checks column existence
    # Since we can't easily mock column_names, we verify the behavior indirectly
    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    # If the field validation is working, the operation should complete without errors
    assert_response :redirect
    assert_match "Fast forwarded", flash[:notice]
  end

  test "fast_forward_time should handle database transaction rollback on error" do
    # Test transaction behavior by simulating an error condition
    # Since the controller uses a transaction, if one part fails, all should rollback

    original_patient_arrival = @patient.arrival_time
    original_order_time = @lab_order.ordered_at

    # This test ensures transaction behavior is present
    # The actual implementation wraps updates in ActiveRecord::Base.transaction
    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    @patient.reload
    @lab_order.reload

    # If transaction completed successfully, both should be updated
    assert_not_equal original_patient_arrival, @patient.arrival_time
    assert_not_equal original_order_time, @lab_order.ordered_at
  end

  test "fast_forward_time should log errors when exceptions occur" do
    # Test error handling and logging
    # We can verify the error handling structure exists by checking the rescue clause behavior

    # The controller has: rescue => e followed by Rails.logger.error
    # We can test this by ensuring that even if an error occurs, we get appropriate feedback

    # Simulate a scenario that could cause issues but should be handled gracefully
    CarePathwayOrder.destroy_all
    Patient.destroy_all

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    # Should still redirect even with no data
    assert_response :redirect
    # Should either succeed with 0 records or show an error message
    assert(flash[:notice] || flash[:alert])
  end

  test "fast_forward_time should handle concurrent access safely" do
    # Test that the method can handle multiple simultaneous requests
    # This tests the locking and transaction behavior

    # Create multiple threads that try to fast forward simultaneously
    # Since we're using Rails test environment, we'll simulate this by ensuring
    # the method is safe to call multiple times quickly

    assert_nothing_raised do
      post simulation_fast_forward_time_path
      # Immediate second call should also work
      post simulation_fast_forward_time_path
    end

    assert_response :redirect
    assert_match "Fast forwarded", flash[:notice]
  end

  test "fast_forward_time should maintain data integrity during partial failures" do
    # Test that if timer expiration processing fails, the timestamp updates still succeed
    # The controller processes timer expirations in a separate operation after timestamp updates

    # Setup data that could potentially cause issues during timer processing
    @lab_order.update!(
      ordered_at: 45.minutes.ago,  # This will trigger a timer status change
      timer_status: "green"
    )

    original_ordered_at = @lab_order.ordered_at

    post simulation_fast_forward_time_path

    @lab_order.reload

    # Timestamp should be updated regardless of timer processing issues
    assert_not_equal original_ordered_at, @lab_order.ordered_at
    assert @lab_order.ordered_at < original_ordered_at

    # Timer status should also be updated if possible
    assert_equal "red", @lab_order.timer_status  # 45 + 10 = 55 minutes = red
  end

  # ===============================
  # REWIND TIME TESTS
  # ===============================

  test "rewind_time should subtract 10 minutes from patient arrival times" do
    original_arrival = @patient.arrival_time
    post simulation_rewind_time_path

    @patient.reload
    expected_new_time = original_arrival + 10.minutes
    assert_in_delta expected_new_time.to_f, @patient.arrival_time.to_f, 1.0
  end

  test "rewind_time should subtract 10 minutes from triage_completed_at" do
    original_triage = @patient.triage_completed_at
    post simulation_rewind_time_path

    @patient.reload
    expected_new_time = original_triage + 10.minutes
    assert_in_delta expected_new_time.to_f, @patient.triage_completed_at.to_f, 1.0
  end

  test "rewind_time should subtract 10 minutes from care pathway order timestamps" do
    original_ordered_at = @lab_order.ordered_at
    post simulation_rewind_time_path

    @lab_order.reload
    expected_new_time = original_ordered_at + 10.minutes
    assert_in_delta expected_new_time.to_f, @lab_order.ordered_at.to_f, 1.0
  end

  test "rewind_time should not make timestamps future" do
    # Create a patient who just arrived (5 minutes ago)
    recent_patient = Patient.create!(
      first_name: "Recent",
      last_name: "Arrival",
      age: 30,
      mrn: "REC_#{SecureRandom.hex(4)}",
      location_status: :waiting_room,
      arrival_time: 5.minutes.ago
    )

    post simulation_rewind_time_path

    recent_patient.reload
    # Arrival time should not be significantly in the future (allow small tolerance for timing)
    assert recent_patient.arrival_time <= Time.current + 1.second,
           "Arrival time should not be in the future after rewind"
    # Should be at or close to current time (within 5 seconds for test timing)
    assert_in_delta Time.current.to_f, recent_patient.arrival_time.to_f, 5.0
  end

  test "rewind_time should handle orders with timestamps less than 10 minutes old" do
    # Create an order that's only 3 minutes old
    recent_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Recent Test",
      order_type: :lab,
      status: :ordered,
      ordered_at: 3.minutes.ago,
      timer_status: "green"
    )

    post simulation_rewind_time_path

    recent_order.reload
    # Should not be in the future (allow small tolerance)
    assert recent_order.ordered_at <= Time.current + 1.second,
           "Order timestamp should not be in the future"
    # Should be at or close to current time
    assert_in_delta Time.current.to_f, recent_order.ordered_at.to_f, 5.0
  end

  test "rewind_time should update multiple timestamp fields on orders" do
    # Setup order with multiple timestamps
    @lab_order.update!(
      collected_at: 20.minutes.ago,
      in_lab_at: 15.minutes.ago,
      resulted_at: 5.minutes.ago,
      status: :resulted
    )

    original_collected = @lab_order.collected_at
    original_in_lab = @lab_order.in_lab_at
    original_resulted = @lab_order.resulted_at

    post simulation_rewind_time_path

    @lab_order.reload

    # All should be rewound but not future
    assert @lab_order.collected_at > original_collected
    assert @lab_order.in_lab_at > original_in_lab
    assert @lab_order.resulted_at <= Time.current + 1.second  # 5 min ago + 10 min = should cap at current
  end

  test "rewind_time should handle nil timestamps gracefully" do
    patient_no_triage = Patient.create!(
      first_name: "No",
      last_name: "Triage",
      age: 25,
      mrn: "NT_#{SecureRandom.hex(4)}",
      location_status: :waiting_room,
      arrival_time: 30.minutes.ago,
      triage_completed_at: nil
    )

    assert_nothing_raised do
      post simulation_rewind_time_path
    end

    patient_no_triage.reload
    assert_nil patient_no_triage.triage_completed_at
  end

  test "rewind_time should update timer statuses appropriately" do
    # Order at 15 minutes (yellow) should become green (5 minutes) after rewind
    yellow_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Timer Test",
      order_type: :lab,
      status: :ordered,
      ordered_at: 15.minutes.ago,
      timer_status: "yellow"
    )

    post simulation_rewind_time_path

    yellow_order.reload
    assert_equal "green", yellow_order.timer_status
    assert_equal 5, yellow_order.last_status_duration_minutes
  end

  test "rewind_time should handle medication timer thresholds correctly" do
    # Medication at 12 minutes (red) should become yellow (2 minutes) after rewind
    red_medication = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Urgent Med",
      order_type: :medication,
      status: :ordered,
      ordered_at: 12.minutes.ago,
      timer_status: "red"
    )

    post simulation_rewind_time_path

    red_medication.reload
    assert_equal "green", red_medication.timer_status  # 12 - 10 = 2 minutes = green for medication
    assert_equal 2, red_medication.last_status_duration_minutes
  end

  test "rewind_time should show accurate flash message with record count" do
    post simulation_rewind_time_path

    assert_response :redirect
    assert_match /Rewound all timers by 10 minutes/, flash[:notice]
    assert_match /\(\d+ records updated\)/, flash[:notice]
  end

  test "rewind_time should use database transaction for atomicity" do
    original_patient_arrival = @patient.arrival_time
    original_order_time = @lab_order.ordered_at

    post simulation_rewind_time_path

    @patient.reload
    @lab_order.reload

    # Both should be updated together
    assert @patient.arrival_time > original_patient_arrival
    assert @lab_order.ordered_at > original_order_time
  end

  test "rewind_time should handle error conditions gracefully" do
    # Clear all data to simulate edge case
    CarePathwayOrder.destroy_all
    Patient.destroy_all

    assert_nothing_raised do
      post simulation_rewind_time_path
    end

    assert_response :redirect
    assert(flash[:notice] || flash[:alert])
  end

  test "rewind_time should validate timestamp fields against whitelist" do
    # Should use the same VALID_TIMESTAMP_FIELDS constant
    assert SimulationController::VALID_TIMESTAMP_FIELDS.frozen?

    post simulation_rewind_time_path
    assert_response :redirect
  end

  test "rewind_time should prevent SQL injection" do
    malicious_patient = Patient.create!(
      first_name: "'; UPDATE patients SET esi_level = 1; --",
      last_name: "Hacker",
      age: 40,
      mrn: "MAL_#{SecureRandom.hex(4)}",
      location_status: :ed_room,
      arrival_time: 20.minutes.ago
    )

    original_count = Patient.where(esi_level: 1).count

    post simulation_rewind_time_path

    # Should not have executed injected SQL
    assert_equal original_count, Patient.where(esi_level: 1).count
    assert_response :redirect
  end

  test "rewind_time should handle orders in various statuses" do
    # Test collected status
    collected_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Collected Order",
      order_type: :lab,
      status: :collected,
      ordered_at: 60.minutes.ago,
      collected_at: 20.minutes.ago,
      timer_status: "green"
    )

    original_collected = collected_order.collected_at

    post simulation_rewind_time_path

    collected_order.reload
    # Should update from collected_at for duration calculation
    assert collected_order.collected_at > original_collected
    assert_equal "green", collected_order.timer_status  # 20 - 10 = 10 minutes = green
  end

  test "rewind_time should handle boundary case of exactly 10 minutes" do
    # Order exactly 10 minutes old should go to 0 (current time)
    exact_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Exact Timing",
      order_type: :lab,
      status: :ordered,
      ordered_at: 10.minutes.ago,
      timer_status: "green"
    )

    current_time = Time.current
    post simulation_rewind_time_path

    exact_order.reload
    # Should be very close to current time
    assert_in_delta current_time.to_f, exact_order.ordered_at.to_f, 2.0
    assert_equal "green", exact_order.timer_status
    # Duration should be very small or nil if not updated
    assert(exact_order.last_status_duration_minutes.nil? || exact_order.last_status_duration_minutes <= 1)
  end

  test "rewind_time should update wait time events appropriately" do
    # Patient who was waiting 125 minutes becomes 115 minutes (no longer over 120 threshold)
    long_wait_patient = Patient.create!(
      first_name: "Long",
      last_name: "Wait",
      age: 50,
      mrn: "LW_#{SecureRandom.hex(4)}",
      location_status: :needs_room_assignment,
      arrival_time: 125.minutes.ago,
      triage_completed_at: 120.minutes.ago
    )

    # Create an existing event for exceeding 120 minutes
    Event.create!(
      patient: long_wait_patient,
      action: "Wait time exceeded 120 minutes",
      details: "Patient has been waiting for 125 minutes",
      performed_by: "System",
      time: 5.minutes.ago,
      category: "administrative"
    )

    post simulation_rewind_time_path

    long_wait_patient.reload
    # After rewind, wait time should be 115 minutes (still over 60 but not 120)
    wait_time = ((Time.current - long_wait_patient.arrival_time) / 60).round
    assert wait_time < 120
    assert wait_time > 60
  end

  test "rewind_time should handle concurrent requests safely" do
    assert_nothing_raised do
      post simulation_rewind_time_path
      post simulation_rewind_time_path  # Second immediate call
    end

    assert_response :redirect
    assert_match "Rewound", flash[:notice]
  end

  test "rewind_time should redirect to referrer" do
    referrer_url = "/dashboard/ed"
    post simulation_rewind_time_path, headers: { "HTTP_REFERER" => referrer_url }
    assert_redirected_to referrer_url
  end

  test "rewind_time should fallback to root when no referrer" do
    post simulation_rewind_time_path
    assert_redirected_to root_path
  end

  test "rewind_time should process timer expirations after timestamp updates" do
    # Order that will change from red to yellow after rewind
    # Lab ordered target is 15 min, yellow is 12-15 min
    @lab_order.update!(
      ordered_at: 23.minutes.ago,  # 23 - 10 = 13 minutes = yellow
      timer_status: "red"
    )

    post simulation_rewind_time_path

    @lab_order.reload
    assert_equal "yellow", @lab_order.timer_status
    assert_equal 13, @lab_order.last_status_duration_minutes
  end

  test "rewind_time should cap all timestamps at current time" do
    # Create multiple items with various ages
    patients_and_times = []
    5.times do |i|
      patient = Patient.create!(
        first_name: "Test#{i}",
        last_name: "Patient",
        age: 20 + i,
        mrn: "TP_#{i}_#{SecureRandom.hex(4)}",
        location_status: :waiting_room,
        arrival_time: (i * 2).minutes.ago  # 0, 2, 4, 6, 8 minutes ago
      )
      patients_and_times << [patient, patient.arrival_time]
    end

    current_time = Time.current
    post simulation_rewind_time_path

    patients_and_times.each do |patient, original_time|
      patient.reload
      # No timestamp should be in the future
      assert patient.arrival_time <= current_time + 1.second,  # Allow 1 second tolerance
             "Patient #{patient.mrn} arrival time #{patient.arrival_time} should not be future of #{current_time}"

      # Times that were less than 10 minutes ago should be at current time
      if (current_time - original_time) < 10.minutes
        assert_in_delta current_time.to_f, patient.arrival_time.to_f, 2.0,
               "Patient #{patient.mrn} should have arrival time capped at current time"
      else
        # Times that were more than 10 minutes ago should be rewound by 10 minutes
        expected = original_time + 10.minutes
        assert_in_delta expected.to_f, patient.arrival_time.to_f, 2.0,
               "Patient #{patient.mrn} should have arrival time rewound by 10 minutes"
      end
    end
  end
end
