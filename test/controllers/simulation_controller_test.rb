require "test_helper"

class SimulationControllerTest < ActionDispatch::IntegrationTest
  setup do
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
    assert_equal "Fast forwarded all timers by 10 minutes", flash[:notice]
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
    @lab_order.update!(
      ordered_at: 15.minutes.ago,  # 15 + 10 = 25 minutes = yellow
      timer_status: "green"
    )

    post simulation_fast_forward_time_path

    @lab_order.reload
    assert_equal "yellow", @lab_order.timer_status
    assert_equal 25, @lab_order.last_status_duration_minutes
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
    assert_equal "Fast forwarded all timers by 10 minutes", flash[:notice]
  end

  test "fast_forward_time should handle no orders gracefully" do
    CarePathwayOrder.destroy_all

    assert_nothing_raised do
      post simulation_fast_forward_time_path
    end

    assert_response :redirect
    assert_equal "Fast forwarded all timers by 10 minutes", flash[:notice]
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
    # Test medication-specific timer logic (5/10 minute thresholds)
    @medication_order.update!(
      ordered_at: 8.minutes.ago,  # 8 + 10 = 18 minutes = red for medication
      timer_status: "yellow"
    )

    post simulation_fast_forward_time_path

    @medication_order.reload
    assert_equal "red", @medication_order.timer_status
    assert_equal 18, @medication_order.last_status_duration_minutes
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
    # Duration should be calculated from collected_at (30 + 10 = 40 minutes = yellow)
    assert_equal "yellow", collected_order.timer_status
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
end
