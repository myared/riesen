require "test_helper"

class PatientTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.new(
      first_name: "John",
      last_name: "Doe",
      age: 30,
      mrn: "PT_#{SecureRandom.hex(4)}",
      esi_level: 3,
      pain_score: 5,
      location: "Waiting Room",
      chief_complaint: "Headache",
      arrival_time: Time.current
    )
  end

  test "should be valid with valid attributes" do
    assert @patient.valid?
  end

  test "should require first name" do
    @patient.first_name = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:first_name], "can't be blank"
  end

  test "should require last name" do
    @patient.last_name = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:last_name], "can't be blank"
  end

  test "should require age" do
    @patient.age = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:age], "can't be blank"
  end

  test "age should be greater than 0" do
    @patient.age = 0
    assert_not @patient.valid?
    @patient.age = -1
    assert_not @patient.valid?
    @patient.age = 1
    assert @patient.valid?
  end

  test "should require mrn" do
    @patient.mrn = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:mrn], "can't be blank"
  end

  test "mrn should be unique" do
    @patient.save!
    duplicate_patient = @patient.dup
    assert_not duplicate_patient.valid?
    assert_includes duplicate_patient.errors[:mrn], "has already been taken"
  end

  test "esi_level should be between 1 and 5" do
    @patient.esi_level = 0
    assert_not @patient.valid?
    @patient.esi_level = 6
    assert_not @patient.valid?
    (1..5).each do |level|
      @patient.esi_level = level
      assert @patient.valid?
    end
  end

  test "pain_score should be between 1 and 10" do
    @patient.pain_score = 0
    assert_not @patient.valid?
    @patient.pain_score = 11
    assert_not @patient.valid?
    (1..10).each do |score|
      @patient.pain_score = score
      assert @patient.valid?
    end
  end

  test "full_name returns first and last name" do
    assert_equal "John Doe", @patient.full_name
  end

  test "wait_progress_percentage calculates correctly" do
    @patient.esi_level = 3
    @patient.arrival_time = 15.minutes.ago
    assert_equal 50, @patient.wait_progress_percentage

    @patient.arrival_time = 30.minutes.ago
    assert_equal 100, @patient.wait_progress_percentage

    @patient.arrival_time = 45.minutes.ago
    assert_equal 100, @patient.wait_progress_percentage
  end

  test "latest_vital returns most recent vital" do
    @patient.save!
    old_vital = @patient.vitals.create!(
      heart_rate: 70,
      recorded_at: 1.hour.ago
    )
    new_vital = @patient.vitals.create!(
      heart_rate: 80,
      recorded_at: Time.current
    )

    assert_equal new_vital, @patient.latest_vital
  end

  test "should destroy associated vitals when destroyed" do
    @patient.save!
    @patient.vitals.create!(heart_rate: 70, recorded_at: Time.current)

    assert_difference "Vital.count", -1 do
      @patient.destroy
    end
  end

  test "should destroy associated events when destroyed" do
    @patient.save!
    @patient.events.create!(
      action: "Arrived",
      performed_by: "Registration",
      time: Time.current
    )

    assert_difference "Event.count", -1 do
      @patient.destroy
    end
  end

  test "intake_complete? returns false when triage is not completed" do
    @patient.triage_completed_at = nil
    @patient.esi_level = 3
    assert_not @patient.intake_complete?
  end

  test "intake_complete? returns false when ESI level is not set" do
    @patient.triage_completed_at = Time.current
    @patient.esi_level = nil
    assert_not @patient.intake_complete?
  end

  test "intake_complete? returns true when both triage is completed and ESI level is set" do
    @patient.triage_completed_at = Time.current
    @patient.esi_level = 3
    assert @patient.intake_complete?
  end

  test "location_status enum and scopes" do
    @patient.save!

    # Test default status
    assert @patient.location_waiting_room?

    # Test enum transitions
    @patient.update!(location_status: :triage)
    assert @patient.location_triage?

    @patient.update!(location_status: :needs_room_assignment)
    assert @patient.location_needs_room_assignment?

    @patient.update!(location_status: :results_pending)
    assert @patient.location_results_pending?

    @patient.update!(location_status: :ed_room)
    assert @patient.location_ed_room?

    @patient.update!(location_status: :treatment)
    assert @patient.location_treatment?

    @patient.update!(location_status: :discharged)
    assert @patient.location_discharged?
  end

  test "scopes filter patients correctly" do
    @patient.save!

    # Create patients with different statuses
    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Patient", age: 25, mrn: "WAIT001",
      location_status: :waiting_room, esi_level: 3
    )

    triage_patient = Patient.create!(
      first_name: "Triage", last_name: "Patient", age: 30, mrn: "TRIAGE001",
      location_status: :triage, esi_level: 4
    )

    ed_patient = Patient.create!(
      first_name: "ED", last_name: "Patient", age: 35, mrn: "ED001",
      location_status: :ed_room, esi_level: 2
    )

    treatment_patient = Patient.create!(
      first_name: "Treatment", last_name: "Patient", age: 40, mrn: "TREAT001",
      location_status: :treatment, esi_level: 3
    )

    provider_patient = Patient.create!(
      first_name: "Provider", last_name: "Patient", age: 45, mrn: "PROV001",
      location_status: :ed_room, provider: "Dr. Smith", esi_level: 2
    )

    critical_patient = Patient.create!(
      first_name: "Critical", last_name: "Patient", age: 50, mrn: "CRIT001",
      location_status: :ed_room, esi_level: 1
    )

    # Test waiting scope
    waiting_patients = Patient.waiting
    assert_includes waiting_patients, waiting_patient
    assert_not_includes waiting_patients, triage_patient
    assert_not_includes waiting_patients, ed_patient

    # Test in_triage scope
    in_triage_patients = Patient.in_triage
    assert_includes in_triage_patients, waiting_patient
    assert_includes in_triage_patients, triage_patient
    assert_not_includes in_triage_patients, ed_patient

    # Test in_ed scope
    in_ed_patients = Patient.in_ed
    assert_includes in_ed_patients, ed_patient
    assert_includes in_ed_patients, treatment_patient
    assert_includes in_ed_patients, provider_patient
    assert_includes in_ed_patients, critical_patient
    assert_not_includes in_ed_patients, waiting_patient

    # Test with_provider scope
    with_provider_patients = Patient.with_provider
    assert_includes with_provider_patients, provider_patient
    assert_not_includes with_provider_patients, ed_patient

    # Test critical scope (ESI 1 and 2)
    critical_patients = Patient.critical
    assert_includes critical_patients, critical_patient
    assert_includes critical_patients, ed_patient  # ESI 2 is also critical
    assert_includes critical_patients, provider_patient  # ESI 2 is also critical
    assert_not_includes critical_patients, waiting_patient  # ESI 3 is not critical
  end

  test "esi_target_minutes returns correct targets" do
    assert_equal 0, Patient.new(esi_level: 1).esi_target_minutes
    assert_equal 10, Patient.new(esi_level: 2).esi_target_minutes
    assert_equal 30, Patient.new(esi_level: 3).esi_target_minutes
    assert_equal 60, Patient.new(esi_level: 4).esi_target_minutes
    assert_equal 120, Patient.new(esi_level: 5).esi_target_minutes
    assert_equal 30, Patient.new(esi_level: nil).esi_target_minutes # default
  end

  test "esi_target_label returns correct labels" do
    assert_equal "Immediate", Patient.new(esi_level: 1).esi_target_label
    assert_equal "10m target", Patient.new(esi_level: 2).esi_target_label
    assert_equal "30m target", Patient.new(esi_level: 3).esi_target_label
    assert_equal "60m target", Patient.new(esi_level: 4).esi_target_label
    assert_equal "120m target", Patient.new(esi_level: 5).esi_target_label
  end

  test "esi_description returns correct descriptions" do
    assert_equal "Resuscitation", Patient.new(esi_level: 1).esi_description
    assert_equal "Emergent", Patient.new(esi_level: 2).esi_description
    assert_equal "Urgent", Patient.new(esi_level: 3).esi_description
    assert_equal "Less Urgent", Patient.new(esi_level: 4).esi_description
    assert_equal "Non-Urgent", Patient.new(esi_level: 5).esi_description
  end

  test "overdue? returns correct status" do
    # Patient not overdue
    patient = Patient.new(esi_level: 3, arrival_time: 20.minutes.ago)
    assert_not patient.overdue?

    # Patient overdue
    patient.arrival_time = 45.minutes.ago
    assert patient.overdue?

    # Critical patient should be overdue immediately
    patient = Patient.new(esi_level: 1, arrival_time: 1.minute.ago)
    assert patient.overdue?
  end

  test "critical? returns correct status" do
    assert Patient.new(esi_level: 1).critical?
    assert Patient.new(esi_level: 2).critical?
    assert_not Patient.new(esi_level: 3).critical?
    assert_not Patient.new(esi_level: 4).critical?
    assert_not Patient.new(esi_level: 5).critical?
  end

  test "room assignment workflow" do
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: false)
    room_number = "ED_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :ed, status: :available)

    # Assign room via Room model
    room.assign_patient(@patient)
    @patient.reload

    # Check patient status updated correctly
    assert @patient.location_ed_room?
    assert_equal room_number, @patient.room_number
  end

  test "rp eligible patient workflow" do
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: true)
    room_number = "RP_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :rp, status: :available)

    # Assign room via Room model
    room.assign_patient(@patient)
    @patient.reload

    # Check patient status updated correctly for RP
    assert @patient.location_results_pending?
    assert_equal room_number, @patient.room_number
  end

  test "patient transitions through complete workflow" do
    @patient.save!

    # Start in waiting room
    assert @patient.location_waiting_room?

    # Move to triage
    @patient.update!(location_status: :triage)
    assert @patient.location_triage?

    # Complete triage, needs room assignment
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: false)
    assert @patient.location_needs_room_assignment?

    # Assign to ED room
    @patient.update!(location_status: :ed_room, room_number: "ED01")
    assert @patient.location_ed_room?
    assert_equal "ED01", @patient.room_number

    # Move to treatment
    @patient.update!(location_status: :treatment)
    assert @patient.location_treatment?

    # Discharge
    @patient.update!(location_status: :discharged, room_number: nil)
    assert @patient.location_discharged?
    assert_nil @patient.room_number
  end

  test "rp_eligible boolean field works correctly" do
    @patient.save!

    # Test nil value (should be falsy)
    assert_not @patient.rp_eligible

    # Test false value
    @patient.update!(rp_eligible: false)
    assert_not @patient.rp_eligible

    # Test true value
    @patient.update!(rp_eligible: true)
    assert @patient.rp_eligible
  end

  test "patient can have multiple vitals over time" do
    @patient.save!

    # Create initial vitals
    vital1 = @patient.vitals.create!(
      heart_rate: 72,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      recorded_at: 2.hours.ago
    )

    # Create updated vitals
    vital2 = @patient.vitals.create!(
      heart_rate: 85,
      blood_pressure_systolic: 130,
      blood_pressure_diastolic: 85,
      recorded_at: 1.hour.ago
    )

    # Latest vital should be the most recent
    assert_equal vital2, @patient.latest_vital
    assert_equal 2, @patient.vitals.count
  end

  test "patient can have multiple events" do
    @patient.save!

    # Create arrival event
    event1 = @patient.events.create!(
      action: "Arrival",
      details: "Patient arrived via ambulance",
      performed_by: "Registration",
      time: 2.hours.ago,
      category: "administrative"
    )

    # Create triage event
    event2 = @patient.events.create!(
      action: "Triage completed",
      details: "ESI 3 assigned",
      performed_by: "Triage RN",
      time: 1.hour.ago,
      category: "clinical"
    )

    assert_equal 2, @patient.events.count
    assert_includes @patient.events, event1
    assert_includes @patient.events, event2
  end

  test "wait_progress_percentage handles edge cases" do
    # ESI 1 (immediate) should show 100% immediately
    patient = Patient.new(esi_level: 1, arrival_time: Time.current)
    assert_equal 100, patient.wait_progress_percentage

    # Very long wait should cap at 100%
    patient = Patient.new(esi_level: 3, arrival_time: 1000.minutes.ago)
    assert_equal 100, patient.wait_progress_percentage

    # Zero wait time
    patient = Patient.new(esi_level: 3, arrival_time: Time.current)
    assert_equal 0, patient.wait_progress_percentage
  end

  test "patient associations work correctly" do
    @patient.save!

    # Test care pathways association
    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :not_started
    )

    assert_includes @patient.care_pathways, pathway

    # Test active care pathway
    pathway.update!(status: :in_progress)
    @patient.reload # Reload to ensure association is fresh
    assert_equal pathway, @patient.active_care_pathway

    # Test completed pathway doesn't show as active
    pathway.update!(status: :completed)
    @patient.reload # Reload to ensure association is fresh
    assert_nil @patient.active_care_pathway
  end

  test "room_assignment_needed_at attribute works correctly" do
    @patient.save!

    # Initially should be nil
    assert_nil @patient.room_assignment_needed_at

    # Should be able to set the timestamp
    timestamp = 30.minutes.ago
    @patient.update!(room_assignment_needed_at: timestamp)
    @patient.reload
    assert_equal timestamp.to_i, @patient.room_assignment_needed_at.to_i

    # Should be able to clear the timestamp
    @patient.update!(room_assignment_needed_at: nil)
    @patient.reload
    assert_nil @patient.room_assignment_needed_at
  end

  test "room_assignment_needed_at can be set to current time" do
    @patient.save!

    freeze_time do
      @patient.update!(room_assignment_needed_at: Time.current)
      @patient.reload
      assert_equal Time.current.to_f, @patient.room_assignment_needed_at.to_f
    end
  end

  test "room_assignment_needed_at persists correctly" do
    @patient.save!

    # Set a specific timestamp
    specific_time = Time.parse("2023-10-15 14:30:00 UTC")
    @patient.update!(room_assignment_needed_at: specific_time)

    # Reload from database
    @patient.reload
    assert_equal specific_time, @patient.room_assignment_needed_at

    # Verify it works with other patient operations
    @patient.update!(esi_level: 2)
    @patient.reload
    assert_equal specific_time, @patient.room_assignment_needed_at
    assert_equal 2, @patient.esi_level
  end

  test "room_assignment_needed_at works with location_needs_room_assignment status" do
    @patient.save!

    # Set to needs room assignment and timestamp
    freeze_time do
      @patient.update!(
        location_status: :needs_room_assignment,
        room_assignment_needed_at: Time.current,
        triage_completed_at: Time.current
      )

      @patient.reload
      assert @patient.location_needs_room_assignment?
      assert_equal Time.current.to_f, @patient.room_assignment_needed_at.to_f
      assert_equal Time.current.to_f, @patient.triage_completed_at.to_f
    end
  end

  test "room_assignment_needed_at can be used to calculate wait time for room assignment" do
    @patient.save!

    # Set timestamp to 45 minutes ago
    @patient.update!(
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 45.minutes.ago
    )

    # Calculate minutes waiting (this matches the MonitorWaitTimesJob logic)
    minutes_waiting = ((Time.current - @patient.room_assignment_needed_at) / 60).round
    assert_equal 45, minutes_waiting
  end

  test "room_assignment_needed_at integrates with triage workflow" do
    @patient.save!

    # Simulate triage completion workflow
    freeze_time do
      triage_completion_time = Time.current

      @patient.update!(
        location_status: :needs_room_assignment,
        triage_completed_at: triage_completion_time,
        room_assignment_needed_at: triage_completion_time
      )

      @patient.reload

      # Verify workflow state
      assert @patient.location_needs_room_assignment?
      assert_equal triage_completion_time, @patient.triage_completed_at
      assert_equal triage_completion_time, @patient.room_assignment_needed_at
      assert_equal @patient.triage_completed_at, @patient.room_assignment_needed_at

      # Should be able to transition to assigned room
      @patient.update!(
        location_status: :ed_room,
        room_number: "ED01"
      )

      @patient.reload
      assert @patient.location_ed_room?
      assert_equal "ED01", @patient.room_number
      # Timestamps should persist even after room assignment
      assert_equal triage_completion_time, @patient.room_assignment_needed_at
      assert_equal triage_completion_time, @patient.triage_completed_at
    end
  end

  test "room_assignment_needed_at works with different time zones" do
    @patient.save!

    # Test with specific timezone
    eastern_time = Time.parse("2023-10-15 09:30:00 EST")
    @patient.update!(room_assignment_needed_at: eastern_time)

    @patient.reload
    assert_equal eastern_time.utc, @patient.room_assignment_needed_at.utc
  end

  test "room_assignment_needed_at can be queried for monitoring" do
    @patient.save!

    # Create patients with different room assignment timing
    patient1 = Patient.create!(
      first_name: "Room1", last_name: "Patient", age: 30, 
      mrn: "ROOM1_#{SecureRandom.hex(4)}", esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 30.minutes.ago
    )

    patient2 = Patient.create!(
      first_name: "Room2", last_name: "Patient", age: 25, 
      mrn: "ROOM2_#{SecureRandom.hex(4)}", esi_level: 2,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 10.minutes.ago
    )

    patient3 = Patient.create!(
      first_name: "Room3", last_name: "Patient", age: 35, 
      mrn: "ROOM3_#{SecureRandom.hex(4)}", esi_level: 4,
      location_status: :ed_room, # Already assigned
      room_assignment_needed_at: 45.minutes.ago
    )

    # Query for patients needing room assignment
    patients_needing_rooms = Patient.location_needs_room_assignment
    assert_includes patients_needing_rooms, patient1
    assert_includes patients_needing_rooms, patient2
    assert_not_includes patients_needing_rooms, patient3

    # Query for patients waiting longer than 20 minutes
    patients_waiting_long = Patient.where(
      "room_assignment_needed_at < ?", 20.minutes.ago
    ).location_needs_room_assignment

    assert_includes patients_waiting_long, patient1
    assert_not_includes patients_waiting_long, patient2
  end

  # Tests for top_pending_tasks method
  test "top_pending_tasks returns empty array when no pending tasks" do
    @patient.save!
    @patient.update!(
      location_status: :discharged,
      triage_completed_at: 1.hour.ago
    )

    tasks = @patient.top_pending_tasks
    assert_empty tasks
  end

  test "top_pending_tasks includes check-in task when at check-in step" do
    @patient.save!
    @patient.update!(
      arrival_time: 25.minutes.ago,
      triage_completed_at: nil,
      location_status: :waiting_room,
      esi_level: 3
    )

    # Create triage care pathway with Check-In as current step
    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress
    )

    pathway.care_pathway_steps.create!(
      name: 'Check-In',
      sequence: 1,
      completed: false
    )

    tasks = @patient.top_pending_tasks
    assert_equal 1, tasks.length

    task = tasks.first
    assert_equal "Check In", task[:name]
    assert_equal :check_in, task[:type]
    assert_equal 25, task[:elapsed_time]
    assert_equal pathway.id, task[:care_pathway_id]
  end

  test "top_pending_tasks includes room assignment task when at bed assignment step" do
    @patient.save!
    @patient.update!(
      arrival_time: 1.hour.ago,
      triage_completed_at: 30.minutes.ago,
      location_status: :needs_room_assignment,
      esi_level: 3
    )

    # Create triage care pathway with Bed Assignment as current step
    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress
    )

    pathway.care_pathway_steps.create!(
      name: 'Check-In',
      sequence: 1,
      completed: true,
      completed_at: 45.minutes.ago
    )

    pathway.care_pathway_steps.create!(
      name: 'Intake',
      sequence: 2,
      completed: true,
      completed_at: 30.minutes.ago
    )

    pathway.care_pathway_steps.create!(
      name: 'Bed Assignment',
      sequence: 3,
      completed: false
    )

    tasks = @patient.top_pending_tasks
    assert_equal 1, tasks.length

    task = tasks.first
    assert_equal "Bed Assignment", task[:name]
    assert_equal :bed_assignment, task[:type]
    assert_equal 30, task[:elapsed_time]
    assert_equal pathway.id, task[:care_pathway_id]
  end

  test "top_pending_tasks includes RP Eligible task for ED patient" do
    @patient.save!

    freeze_time do
      er_pathway = @patient.care_pathways.create!(
        pathway_type: :emergency_room,
        status: :in_progress
      )

      @patient.update!(
        location_status: :ed_room,
        rp_eligible: true,
        rp_eligibility_started_at: 5.minutes.ago,
        esi_level: 3
      )

      tasks = @patient.top_pending_tasks
      assert tasks.any?, "Expected RP Eligible task to be present"

      rp_task = tasks.find { |t| t[:type] == :rp_eligible }
      refute_nil rp_task, "RP Eligible task should be included"
      assert_equal "RP Eligible", rp_task[:name]
      assert_equal 5, rp_task[:elapsed_time]
      assert_equal :green, rp_task[:status]
      assert_equal er_pathway.id, rp_task[:care_pathway_id]
    end
  end

  test "top_pending_tasks includes active care pathway orders" do
    @patient.save!
    @patient.update!(
      location_status: :ed_room,
      esi_level: 3
    )

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Create active order
    order = pathway.care_pathway_orders.create!(
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: 20.minutes.ago
    )

    tasks = @patient.top_pending_tasks
    assert_equal 1, tasks.length

    task = tasks.first
    assert_includes task[:name], "CBC with Differential"
    assert_equal :order, task[:type]
    assert_equal 20, task[:elapsed_time]
    assert_equal pathway.id, task[:care_pathway_id]
    assert_equal order.id, task[:order_id]
  end

  test "top_pending_tasks sorts by status priority then elapsed time" do
    @patient.save!
    @patient.update!(location_status: :ed_room, esi_level: 3)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    freeze_time do
      # Green task (5 minutes) - target is 15 min for lab, 75% = 11 min warning, so 5 < 11 = green
      green_order = pathway.care_pathway_orders.create!(
        name: "Green Order",
        order_type: :lab,
        status: :ordered,
        ordered_at: 5.minutes.ago
      )

      # Red task (20 minutes) - 20 > 15 = red
      red_order = pathway.care_pathway_orders.create!(
        name: "Red Order",
        order_type: :lab,
        status: :ordered,
        ordered_at: 20.minutes.ago
      )

      # Yellow task (12 minutes) - 12 > 11 (warning) but <= 15 (critical) = yellow
      yellow_order = pathway.care_pathway_orders.create!(
        name: "Yellow Order",
        order_type: :lab,
        status: :ordered,
        ordered_at: 12.minutes.ago
      )

      tasks = @patient.top_pending_tasks
      assert_equal 3, tasks.length

      # Should be sorted by priority (red > yellow > green) then elapsed time
      assert_includes tasks[0][:name], "Red Order"
      assert_equal :red, tasks[0][:status]

      assert_includes tasks[1][:name], "Yellow Order"
      assert_equal :yellow, tasks[1][:status]

      assert_includes tasks[2][:name], "Green Order"
      assert_equal :green, tasks[2][:status]
    end
  end

  test "top_pending_tasks limits results to specified number" do
    @patient.save!
    @patient.update!(location_status: :ed_room, esi_level: 3)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Create 6 orders
    6.times do |i|
      pathway.care_pathway_orders.create!(
        name: "Order #{i + 1}",
        order_type: :lab,
        status: :ordered,
        ordered_at: (10 + i).minutes.ago
      )
    end

    # Test default limit (4)
    tasks = @patient.top_pending_tasks
    assert_equal 4, tasks.length

    # Test custom limit (2)
    tasks = @patient.top_pending_tasks(2)
    assert_equal 2, tasks.length
  end

  test "top_pending_tasks excludes completed orders" do
    @patient.save!
    @patient.update!(location_status: :ed_room, esi_level: 3)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Create active order
    active_order = pathway.care_pathway_orders.create!(
      name: "Active Lab",
      order_type: :lab,
      status: :ordered,
      ordered_at: 20.minutes.ago
    )

    # Create completed orders (should be excluded)
    pathway.care_pathway_orders.create!(
      name: "Completed Lab",
      order_type: :lab,
      status: :resulted,
      ordered_at: 30.minutes.ago
    )

    pathway.care_pathway_orders.create!(
      name: "Administered Med",
      order_type: :medication,
      status: :administered,
      ordered_at: 25.minutes.ago
    )

    pathway.care_pathway_orders.create!(
      name: "Completed Exam",
      order_type: :imaging,
      status: :exam_completed,
      ordered_at: 35.minutes.ago
    )

    tasks = @patient.top_pending_tasks
    assert_equal 1, tasks.length
    assert_includes tasks.first[:name], "Active Lab"
  end

  test "top_pending_tasks handles mixed task types correctly" do
    @patient.save!
    @patient.update!(
      arrival_time: 45.minutes.ago,
      triage_completed_at: 30.minutes.ago,
      location_status: :needs_room_assignment,
      esi_level: 3
    )

    # Create triage pathway with room assignment task
    triage_pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress
    )

    # Add completed steps and current bed assignment step
    triage_pathway.care_pathway_steps.create!(
      name: 'Check-In',
      sequence: 1,
      completed: true,
      completed_at: 40.minutes.ago
    )
    triage_pathway.care_pathway_steps.create!(
      name: 'Intake',
      sequence: 2,
      completed: true,
      completed_at: 30.minutes.ago
    )
    triage_pathway.care_pathway_steps.create!(
      name: 'Bed Assignment',
      sequence: 3,
      completed: false
    )

    # Create ER pathway with order
    er_pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Add order task
    order = er_pathway.care_pathway_orders.create!(
      name: "X-Ray Chest",
      order_type: :imaging,
      status: :ordered,
      ordered_at: 40.minutes.ago
    )

    tasks = @patient.top_pending_tasks
    assert_equal 2, tasks.length

    # Should include both bed assignment and order tasks
    task_types = tasks.map { |t| t[:type] }
    assert_includes task_types, :bed_assignment
    assert_includes task_types, :order
  end

  test "top_pending_tasks calculates correct status for different elapsed times" do
    @patient.save!
    @patient.update!(
      arrival_time: 15.minutes.ago,
      triage_completed_at: nil,
      location_status: :waiting_room,
      esi_level: 3
    )

    # Without a triage pathway, it falls back to "Triage" with 10 minute target
    tasks = @patient.top_pending_tasks
    assert_equal 1, tasks.length

    # 15 minutes elapsed with 10 minute target (fallback) should be red
    assert_equal :red, tasks.first[:status]
  end

  # Tests for helper methods
  test "calculate_task_status returns correct status based on thresholds" do
    @patient.save!

    # Test green status (under warning threshold: 75% of 30 = 22.5 min)
    status = @patient.send(:calculate_task_status, 20, 30)  # 20 min elapsed, 30 min target
    assert_equal :green, status

    # Test yellow status (over warning, under critical: 75%-100% of 30 = 23-30 min)
    status = @patient.send(:calculate_task_status, 25, 30)  # 25 min elapsed, 30 min target
    assert_equal :yellow, status

    # Test red status (over critical threshold: 100% of 30 = 30 min)
    status = @patient.send(:calculate_task_status, 35, 30)  # 35 min elapsed, 30 min target
    assert_equal :red, status
  end

  test "status_priority returns correct priority order" do
    @patient.save!

    assert_equal 0, @patient.send(:status_priority, :red)     # Highest priority
    assert_equal 1, @patient.send(:status_priority, :yellow)  # Medium priority
    assert_equal 2, @patient.send(:status_priority, :green)   # Lowest priority
    assert_equal 3, @patient.send(:status_priority, :unknown) # Unknown status
  end
end
