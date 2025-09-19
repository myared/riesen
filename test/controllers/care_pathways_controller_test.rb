require "test_helper"

class CarePathwaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @patient = Patient.create!(
      first_name: "Care",
      last_name: "Pathway",
      age: 30,
      mrn: "CP_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 1.hour.ago
    )

    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress,
      started_at: 30.minutes.ago,
      started_by: "Triage RN"
    )

    # Create triage steps (4 steps in new workflow)
    @step1 = @care_pathway.care_pathway_steps.create!(
      name: "Check-In",
      sequence: 0,
      completed: true,
      completed_at: 25.minutes.ago
    )

    @step2 = @care_pathway.care_pathway_steps.create!(
      name: "Intake",
      sequence: 1,
      completed: true,
      completed_at: 20.minutes.ago
    )

    @step3 = @care_pathway.care_pathway_steps.create!(
      name: "Bed Assignment",
      sequence: 2,
      completed: false
    )

    @step4 = @care_pathway.care_pathway_steps.create!(
      name: "Pending Transfer",
      sequence: 3,
      completed: false
    )
  end

  test "should get index and redirect to existing care pathway" do
    get patient_care_pathways_url(@patient)
    assert_response :redirect
    assert_redirected_to patient_care_pathway_path(@patient, @care_pathway)
  end

  test "should create new triage pathway if none exists" do
    Patient.destroy_all
    patient = Patient.create!(
      first_name: "New",
      last_name: "Patient",
      age: 25,
      mrn: "NEW_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :waiting_room
    )

    assert_difference "CarePathway.count", 1 do
      get patient_care_pathways_url(patient)
    end

    assert_response :redirect
    care_pathway = patient.care_pathways.first
    assert_equal "triage", care_pathway.pathway_type
  end

  test "should show care pathway" do
    get patient_care_pathway_url(@patient, @care_pathway)
    assert_response :success
  end

  # Main test for room_assignment_needed_at timestamp setting
  test "should set room_assignment_needed_at when pathway completes" do
    freeze_time do
      # Complete bed assignment first to move to pending_transfer
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step3.id}"
      @patient.reload
      assert @patient.location_pending_transfer?

      # Complete pending transfer to finish pathway
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

      assert_response :redirect

      # Check that patient was updated with timestamps
      @patient.reload
      assert @patient.location_needs_room_assignment?
      assert_not_nil @patient.room_assignment_needed_at
    end
  end

  test "should create nursing task when pathway completes" do
    # Complete bed assignment first
    @step3.update!(completed: true)

    # Complete the final step (Pending Transfer) to trigger pathway completion
    assert_difference "NursingTask.count", 1 do
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"
    end

    # Check nursing task was created
    nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
    assert nursing_task.present?
    assert nursing_task.status_pending?
    assert_includes nursing_task.description, "Transport"
    assert_includes nursing_task.description, @patient.full_name
  end

  test "should create events when pathway completes" do
    # Complete bed assignment first
    @step3.update!(completed: true)

    # Complete the final step to trigger pathway completion
    assert_difference "Event.count", 2 do # Step completion + pathway completion
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"
    end

    # Check step completion event
    step_event = Event.where(patient: @patient, action: "Pending Transfer completed").first
    assert step_event.present?
    assert_equal "Triage RN", step_event.performed_by
    assert_equal "triage", step_event.category

    # Check pathway completion event
    pathway_event = Event.where(patient: @patient, action: "Triage pathway completed").first
    assert pathway_event.present?
    assert_equal "Triage RN", pathway_event.performed_by
    assert_equal "triage", pathway_event.category
  end

  test "should handle RP eligible patient correctly" do
    @patient.update!(rp_eligible: true)
    @step3.update!(completed: true)

    freeze_time do
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

      @patient.reload
      assert @patient.location_needs_room_assignment?
      assert_not_nil @patient.room_assignment_needed_at

      # Check that pathway completion event mentions RP
      pathway_event = Event.where(patient: @patient, action: "Triage pathway completed").first
      assert_includes pathway_event.details, "RP placement"

      # Check nursing task assignment
      nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
      assert_equal "RP RN", nursing_task.assigned_to
      assert_includes nursing_task.description, "RP area"
    end
  end

  test "should handle non-RP eligible patient correctly" do
    @patient.update!(rp_eligible: false)
    @step3.update!(completed: true)

    freeze_time do
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

      @patient.reload
      assert @patient.location_needs_room_assignment?
      assert_not_nil @patient.room_assignment_needed_at

      # Check that pathway completion event mentions ED
      pathway_event = Event.where(patient: @patient, action: "Triage pathway completed").first
      assert_includes pathway_event.details, "ED placement"

      # Check nursing task assignment
      nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
      assert_equal "ED RN", nursing_task.assigned_to
      assert_includes nursing_task.description, "ED area"
    end
  end

  test "should not complete pathway if not all steps are done" do
    # Reset the second step to incomplete
    @step2.update!(completed: false, completed_at: nil)

    freeze_time do
      # Complete just the second step
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step2.id}"

      # Check pathway is still in progress
      @care_pathway.reload
      assert @care_pathway.status_in_progress?
      assert_nil @care_pathway.completed_at

      # Check patient location status hasn't changed
      @patient.reload
      assert @patient.location_triage?
      assert_nil @patient.room_assignment_needed_at
    end
  end

  test "should set nursing task priority based on ESI level" do
    # Test urgent priority for critical patient
    @patient.update!(esi_level: 1)
    @step3.update!(completed: true)

    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

    nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
    assert_not_nil nursing_task
    assert nursing_task.priority_urgent?
  end

  test "should handle JSON format requests" do
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step3.id}", 
         as: :json

    assert_response :success
    response_data = JSON.parse(response.body)
    assert response_data["success"]
    assert response_data["progress"].present?
  end

  test "should update pathway status when step completed" do
    # Complete bed assignment first
    @step3.update!(completed: true)

    # Complete the final step
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

    # Check pathway completion
    @care_pathway.reload
    assert @care_pathway.status_completed?
    assert_not_nil @care_pathway.completed_at
    assert_equal "ED RN", @care_pathway.completed_by

    # Check step completion
    @step4.reload
    assert @step4.completed?
    assert_not_nil @step4.completed_at
  end

  test "should ensure room_assignment_needed_at precision" do
    @step3.update!(completed: true)

    freeze_time do
      # Complete pending transfer to set room_assignment_needed_at
      post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

      @patient.reload

      # Check that the timestamp is exactly the current time
      assert_equal Time.current.to_f, @patient.room_assignment_needed_at.to_f,
                   "room_assignment_needed_at should be set to exactly current time"
    end
  end
  
  test "should allow bed assignment override to RP when patient not eligible" do
    # Set patient as not RP eligible initially
    @patient.update!(rp_eligible: false)

    # Override to assign to RP
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step3.id}",
         params: { destination: "rp" }

    assert_response :redirect

    # Check patient is now RP eligible
    @patient.reload
    assert @patient.rp_eligible?, "Patient should be RP eligible after override"
    assert @patient.location_pending_transfer?

    # Check events record the override
    step_event = Event.where(patient: @patient, action: "Bed Assignment completed").first
    assert_includes step_event.details, "RP", "Event should mention RP assignment"

    # Complete pending transfer to create nursing task
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

    # Check nursing task reflects RP assignment
    nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
    assert_not_nil nursing_task
    assert_equal "RP RN", nursing_task.assigned_to
    assert_includes nursing_task.description, "RP area"
  end
  
  test "should allow bed assignment override to ED when patient is RP eligible" do
    # Set patient as RP eligible initially
    @patient.update!(rp_eligible: true)

    # Override to assign to ED
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step3.id}",
         params: { destination: "ed" }

    assert_response :redirect

    # Check patient is now not RP eligible
    @patient.reload
    assert_not @patient.rp_eligible?, "Patient should not be RP eligible after ED override"
    assert @patient.location_pending_transfer?

    # Check events record the override
    step_event = Event.where(patient: @patient, action: "Bed Assignment completed").first
    assert_includes step_event.details, "ED", "Event should mention ED assignment"

    # Complete pending transfer to create nursing task
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step4.id}"

    # Check nursing task reflects ED assignment
    nursing_task = NursingTask.where(patient: @patient, task_type: :room_assignment).first
    assert_not_nil nursing_task
    assert_equal "ED RN", nursing_task.assigned_to
    assert_includes nursing_task.description, "ED area"
  end

  test "should not set room_assignment_needed_at if pathway does not complete" do
    # Reset steps to incomplete
    @step2.update!(completed: false, completed_at: nil)
    @step3.update!(completed: false, completed_at: nil)

    # Complete only first step
    post "/patients/#{@patient.id}/care_pathways/#{@care_pathway.id}/complete_step/#{@step2.id}"

    @patient.reload
    # Should not set the timestamp since pathway is not complete
    assert_nil @patient.room_assignment_needed_at
    assert_nil @patient.triage_completed_at
    assert @patient.location_triage? # Should still be in triage
  end
end