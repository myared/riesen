require "test_helper"

class PatientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 25,
      mrn: "PCT_#{SecureRandom.hex(4)}",
      location: "ED Room",
      esi_level: 2
    )
  end

  test "should get show" do
    get patient_url(@patient)
    assert_response :success
  end

  test "show displays patient name" do
    get patient_url(@patient)
    assert_response :success
    assert_match @patient.full_name, response.body
  end

  test "show includes return path" do
    get patient_url(@patient), headers: { "HTTP_REFERER" => dashboard_triage_url }
    assert_response :success
    assert_select "a.modal-close[href=?]", dashboard_triage_url
  end

  test "show displays patient vitals" do
    @patient.vitals.create!(
      heart_rate: 72,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      recorded_at: Time.current
    )
    
    get patient_url(@patient)
    assert_response :success
    assert_match "72 bpm", response.body
    assert_match "120/80", response.body
  end

  test "show displays patient events" do
    @patient.events.create!(
      action: "Triage completed",
      performed_by: "Triage RN",
      time: Time.current
    )
    
    get patient_url(@patient)
    assert_response :success
    assert_match "Triage completed", response.body
  end

  test "assign_room assigns available ED room to non-RP eligible patient" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    room_number = "ED_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :ed, status: :available)
    
    assert_difference('Event.count') do
      post assign_room_patient_url(@patient)
    end
    
    assert_response :redirect
    assert_match "Room #{room_number} assigned", flash[:notice]
    
    room.reload
    @patient.reload
    
    assert_equal @patient, room.current_patient
    assert room.status_occupied?
    assert @patient.location_ed_room?
    assert_equal room_number, @patient.room_number
  end

  test "assign_room assigns available RP room to RP eligible patient" do
    @patient.update!(rp_eligible: true, location_status: :needs_room_assignment)
    room_number = "RP_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :rp, status: :available)
    
    assert_difference('Event.count') do
      post assign_room_patient_url(@patient)
    end
    
    assert_response :redirect
    assert_match "Room #{room_number} assigned", flash[:notice]
    
    room.reload
    @patient.reload
    
    assert_equal @patient, room.current_patient
    assert room.status_occupied?
    assert @patient.location_results_pending?
    assert_equal room_number, @patient.room_number
  end

  test "assign_room fails when no ED rooms available" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :occupied)
    
    assert_no_difference('Event.count') do
      post assign_room_patient_url(@patient)
    end
    
    assert_response :redirect
    assert_match "No ED rooms available", flash[:alert]
    
    @patient.reload
    assert @patient.location_needs_room_assignment?
    assert_nil @patient.room_number
  end

  test "assign_room fails when no RP rooms available" do
    @patient.update!(rp_eligible: true, location_status: :needs_room_assignment)
    Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :occupied)
    
    assert_no_difference('Event.count') do
      post assign_room_patient_url(@patient)
    end
    
    assert_response :redirect
    assert_match "No RP rooms available", flash[:alert]
    
    @patient.reload
    assert @patient.location_needs_room_assignment?
    assert_nil @patient.room_number
  end

  test "assign_room completes associated nursing task" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    room = Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :available)
    
    task = NursingTask.create!(
      patient: @patient,
      task_type: :room_assignment,
      description: "Transport patient to ED",
      assigned_to: "ED RN",
      priority: :high,
      status: :pending,
      due_at: 30.minutes.from_now
    )
    
    post assign_room_patient_url(@patient)
    
    task.reload
    assert task.status_completed?
    assert_not_nil task.completed_at
  end

  test "assign_room with JSON format returns success" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    room = Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :available)
    
    post assign_room_patient_url(@patient), params: {}, as: :json
    
    assert_response :success
    response_data = JSON.parse(response.body)
    assert response_data["success"]
    assert_equal "ED01", response_data["room"]
  end

  test "assign_room with JSON format returns error when no rooms available" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :occupied)
    
    post assign_room_patient_url(@patient), params: {}, as: :json
    
    assert_response :unprocessable_entity
    response_data = JSON.parse(response.body)
    assert_not response_data["success"]
    assert_equal "No rooms available", response_data["error"]
  end

  test "assign_room handles referrer redirect" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    room = Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :available)
    referrer_url = dashboard_ed_rn_url
    
    post assign_room_patient_url(@patient), headers: { "HTTP_REFERER" => referrer_url }
    
    assert_redirected_to referrer_url
  end

  test "assign_room prefers first available room" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    room1_number = "ED_#{SecureRandom.hex(4)}"
    room2_number = "ED_#{SecureRandom.hex(4)}"
    room1 = Room.create!(number: room1_number, room_type: :ed, status: :available)
    room2 = Room.create!(number: room2_number, room_type: :ed, status: :available)
    
    post assign_room_patient_url(@patient)
    
    room1.reload
    room2.reload
    @patient.reload
    
    # Should assign to first available room
    assert_equal @patient, room1.current_patient
    assert_nil room2.current_patient
    assert_equal room1_number, @patient.room_number
  end

  test "assign_room only looks at appropriate room type" do
    @patient.update!(rp_eligible: false, location_status: :needs_room_assignment)
    rp_room = Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :available)
    
    # No ED rooms available, only RP room
    post assign_room_patient_url(@patient)
    
    assert_response :redirect
    assert_match "No ED rooms available", flash[:alert]
    
    rp_room.reload
    @patient.reload
    
    # RP room should remain unassigned
    assert_nil rp_room.current_patient
    assert_nil @patient.room_number
  end

  test "add_event creates event for patient" do
    event_params = {
      action: "Test Event",
      details: "Test details",
      performed_by: "Test User",
      category: "test"
    }
    
    assert_difference('@patient.events.count') do
      post add_event_patient_url(@patient), params: { event: event_params }
    end
    
    assert_redirected_to patient_path(@patient)
    assert_match "Event added successfully", flash[:notice]
    
    event = @patient.events.last
    assert_equal "Test Event", event.action
    assert_equal "Test details", event.details
    assert_equal "Test User", event.performed_by
    assert_equal "test", event.category
  end

  test "add_event with invalid params shows error" do
    event_params = {
      action: "", # Invalid - blank action
      details: "Test details"
    }
    
    assert_no_difference('@patient.events.count') do
      post add_event_patient_url(@patient), params: { event: event_params }
    end
    
    assert_redirected_to patient_path(@patient)
    assert_match "Failed to add event", flash[:alert]
  end

  test "update_vitals creates vital for patient" do
    vital_params = {
      heart_rate: 75,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      respiratory_rate: 16,
      temperature: 98.6,
      spo2: 98,
      weight: 70.0
    }
    
    assert_difference('@patient.vitals.count') do
      assert_difference('Event.count') do # Should create vitals update event
        patch update_vitals_patient_url(@patient), params: { vital: vital_params }
      end
    end
    
    assert_redirected_to patient_path(@patient)
    assert_match "Vitals updated successfully", flash[:notice]
    
    vital = @patient.vitals.last
    assert_equal 75, vital.heart_rate
    assert_equal 120, vital.blood_pressure_systolic
    assert_equal 80, vital.blood_pressure_diastolic
    
    # Check event was created
    event = Event.last
    assert_equal @patient, event.patient
    assert_match "vitals", event.details.downcase
  end

  test "update_vitals with invalid params shows error" do
    vital_params = {
      heart_rate: "invalid", # Invalid - not a number
      blood_pressure_systolic: 120
    }
    
    assert_no_difference('@patient.vitals.count') do
      assert_no_difference('Event.count') do
        patch update_vitals_patient_url(@patient), params: { vital: vital_params }
      end
    end
    
    assert_redirected_to patient_path(@patient)
    assert_match "Failed to update vitals", flash[:alert]
  end
end