require "test_helper"

class MonitorWaitTimesJobTest < ActiveJob::TestCase
  setup do
    # Clear all patients to ensure clean test environment
    Patient.destroy_all
    NursingTask.destroy_all
  end

  test "should be configured to run in default queue" do
    job = MonitorWaitTimesJob.new
    assert_equal "default", job.queue_name
  end

  test "should reschedule itself after running" do
    freeze_time do
      assert_enqueued_with(job: MonitorWaitTimesJob, at: 30.seconds.from_now) do
        MonitorWaitTimesJob.perform_now
      end
    end
  end

  test "should process all patients in triage status" do
    # Create test patients in triage
    patient1 = Patient.create!(
      first_name: "Triage", last_name: "Patient1", age: 30,
      mrn: "TRIAGE1_#{SecureRandom.hex(4)}", esi_level: 3,
      location_status: :triage, arrival_time: 10.minutes.ago
    )
    patient2 = Patient.create!(
      first_name: "Waiting", last_name: "Patient2", age: 25,
      mrn: "WAIT1_#{SecureRandom.hex(4)}", esi_level: 2,
      location_status: :waiting_room, arrival_time: 5.minutes.ago
    )
    patient3 = Patient.create!(
      first_name: "ED", last_name: "Patient3", age: 35,
      mrn: "ED1_#{SecureRandom.hex(4)}", esi_level: 4,
      location_status: :ed_room, arrival_time: 20.minutes.ago
    )

    # Mock the private methods to verify they're called
    job = MonitorWaitTimesJob.new
    call_count = 0
    
    job.define_singleton_method(:check_and_create_wait_time_alerts) do |patient|
      call_count += 1
    end

    job.define_singleton_method(:check_and_create_room_assignment_alerts) do |patient|
      # Don't count this for triage patients
    end

    job.perform

    # Should call check_and_create_wait_time_alerts for patients in triage (2 patients)
    assert_equal 2, call_count
  end

  test "should process all patients needing room assignment" do
    # Create test patients needing room assignment
    patient1 = Patient.create!(
      first_name: "Room", last_name: "Patient1", age: 30,
      mrn: "ROOM1_#{SecureRandom.hex(4)}", esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 10.minutes.ago
    )
    patient2 = Patient.create!(
      first_name: "Triage", last_name: "Patient2", age: 25,
      mrn: "TRIAGE2_#{SecureRandom.hex(4)}", esi_level: 2,
      location_status: :triage, arrival_time: 5.minutes.ago
    )

    # Mock the private methods to verify they're called
    job = MonitorWaitTimesJob.new
    call_count = 0
    
    job.define_singleton_method(:check_and_create_wait_time_alerts) do |patient|
      # Don't count this for room assignment patients
    end

    job.define_singleton_method(:check_and_create_room_assignment_alerts) do |patient|
      call_count += 1
    end

    job.perform

    # Should call check_and_create_room_assignment_alerts for patients needing room assignment (1 patient)
    assert_equal 1, call_count
  end

  # Tests for wait time alert logic
  test "should create yellow alert when wait time exceeds 75% of ESI target" do
    # ESI 3 target is 30 minutes, 75% is 22.5 minutes
    patient = Patient.create!(
      first_name: "Yellow",
      last_name: "Alert",
      age: 30,
      mrn: "YELLOW_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 25.minutes.ago # Exceeds 75% threshold but not 100%
    )

    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient, task.patient
    assert task.task_type_assessment?
    assert_includes task.description, "WAIT TIME ALERT"
    assert_includes task.description, patient.full_name
    assert_includes task.description, "ESI #{patient.esi_level}"
    assert_equal "Charge RN", task.assigned_to
    assert task.priority_high?
    assert task.status_pending?
    assert task.due_at > Time.current
  end

  test "should create red alert when wait time exceeds 100% of ESI target" do
    # ESI 2 target is 10 minutes, patient has been waiting 15 minutes
    patient = Patient.create!(
      first_name: "Red",
      last_name: "Alert",
      age: 40,
      mrn: "RED_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :triage,
      arrival_time: 15.minutes.ago # Exceeds 100% threshold
    )

    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient, task.patient
    assert task.task_type_assessment?
    assert_includes task.description, "CRITICAL WAIT TIME"
    assert_includes task.description, patient.full_name
    assert_includes task.description, "ESI #{patient.esi_level}"
    assert_equal "Charge RN", task.assigned_to
    assert task.priority_urgent?
    assert task.status_pending?
    assert task.due_at > Time.current
  end

  test "should create red alert immediately for ESI 1 patients" do
    # ESI 1 target is 0 minutes (immediate), any wait time should trigger red alert
    patient = Patient.create!(
      first_name: "ESI1",
      last_name: "Critical",
      age: 50,
      mrn: "ESI1_CRIT_#{SecureRandom.hex(4)}",
      esi_level: 1,
      location_status: :triage,
      arrival_time: 1.minute.ago # Even 1 minute should trigger red alert
    )

    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient, task.patient
    assert_includes task.description, "CRITICAL WAIT TIME"
    assert task.priority_urgent?
  end

  test "should not create duplicate yellow alerts" do
    patient = Patient.create!(
      first_name: "Duplicate",
      last_name: "Yellow",
      age: 30,
      mrn: "DUP_YELLOW_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 25.minutes.ago
    )

    # Create an existing yellow alert
    NursingTask.create!(
      patient: patient,
      task_type: :assessment,
      description: "WAIT TIME ALERT: #{patient.full_name} approaching ESI #{patient.esi_level} target",
      assigned_to: 'Charge RN',
      priority: :high,
      status: :pending,
      due_at: 10.minutes.from_now,
      room_number: patient.location_status.humanize
    )

    # Running the job should not create another yellow alert
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should not create duplicate red alerts" do
    patient = Patient.create!(
      first_name: "Duplicate",
      last_name: "Red",
      age: 40,
      mrn: "DUP_RED_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :triage,
      arrival_time: 15.minutes.ago
    )

    # Create an existing red alert
    NursingTask.create!(
      patient: patient,
      task_type: :assessment,
      description: "CRITICAL WAIT TIME: #{patient.full_name} exceeded ESI #{patient.esi_level} target",
      assigned_to: 'Charge RN',
      priority: :urgent,
      status: :pending,
      due_at: 5.minutes.from_now,
      room_number: patient.location_status.humanize
    )

    # Running the job should not create another red alert
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should not create yellow alert when red alert already exists" do
    patient = Patient.create!(
      first_name: "Red",
      last_name: "Exists",
      age: 30,
      mrn: "RED_EXISTS_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 25.minutes.ago # Would normally trigger yellow
    )

    # Create an existing red alert
    NursingTask.create!(
      patient: patient,
      task_type: :assessment,
      description: "CRITICAL WAIT TIME: #{patient.full_name} exceeded ESI #{patient.esi_level} target",
      assigned_to: 'Charge RN',
      priority: :urgent,
      status: :pending,
      due_at: 5.minutes.from_now,
      room_number: patient.location_status.humanize
    )

    # Running the job should not create a yellow alert when red alert exists
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should skip patients without ESI level" do
    patient = Patient.create!(
      first_name: "No",
      last_name: "ESI",
      age: 30,
      mrn: "NO_ESI_#{SecureRandom.hex(4)}",
      esi_level: nil,
      location_status: :triage,
      arrival_time: 60.minutes.ago
    )

    # Should not create any alerts for patients without ESI level
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  # Tests for room assignment alert logic
  test "should create yellow room assignment alert after 15 minutes" do
    patient = Patient.create!(
      first_name: "Room",
      last_name: "Yellow",
      age: 30,
      mrn: "ROOM_YELLOW_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 18.minutes.ago # Exceeds 15 minute threshold
    )

    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient, task.patient
    assert task.task_type_room_assignment?
    assert_includes task.description, "ROOM ASSIGNMENT DELAYED"
    assert_includes task.description, patient.full_name
    assert_includes task.description, "18 minutes"
    assert_equal "Charge RN", task.assigned_to
    assert task.priority_high?
    assert task.status_pending?
    assert_equal "Awaiting Room", task.room_number
  end

  test "should create red room assignment alert after 20 minutes" do
    patient = Patient.create!(
      first_name: "Room",
      last_name: "Red",
      age: 35,
      mrn: "ROOM_RED_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 25.minutes.ago # Exceeds 20 minute threshold
    )

    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient, task.patient
    assert task.task_type_room_assignment?
    assert_includes task.description, "CRITICAL ROOM DELAY"
    assert_includes task.description, patient.full_name
    assert_includes task.description, "25 minutes"
    assert_equal "Charge RN", task.assigned_to
    assert task.priority_urgent?
    assert task.status_pending?
    assert_equal "Awaiting Room", task.room_number
    assert_equal Time.current.to_i, task.due_at.to_i # Due immediately
  end

  test "should not create duplicate room assignment alerts" do
    patient = Patient.create!(
      first_name: "Room",
      last_name: "Duplicate",
      age: 30,
      mrn: "ROOM_DUP_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 18.minutes.ago
    )

    # Create an existing room assignment alert
    NursingTask.create!(
      patient: patient,
      task_type: :room_assignment,
      description: "ROOM ASSIGNMENT DELAYED: #{patient.full_name} waiting 18 minutes",
      assigned_to: 'Charge RN',
      priority: :high,
      status: :pending,
      due_at: 5.minutes.from_now,
      room_number: "Awaiting Room"
    )

    # Running the job should not create another alert
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should skip room assignment alerts for patients without room_assignment_needed_at" do
    patient = Patient.create!(
      first_name: "No",
      last_name: "Timestamp",
      age: 30,
      mrn: "NO_TIMESTAMP_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: nil
    )

    # Should not create any alerts for patients without room_assignment_needed_at
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should not create room assignment yellow alert when red alert exists" do
    patient = Patient.create!(
      first_name: "Room",
      last_name: "RedExists",
      age: 30,
      mrn: "ROOM_RED_EXISTS_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      room_assignment_needed_at: 18.minutes.ago # Would normally trigger yellow
    )

    # Create an existing red alert with the correct minutes count
    NursingTask.create!(
      patient: patient,
      task_type: :room_assignment,
      description: "CRITICAL ROOM DELAY: #{patient.full_name} waiting 18 minutes",
      assigned_to: 'Charge RN',
      priority: :urgent,
      status: :pending,
      due_at: Time.current,
      room_number: "Awaiting Room"
    )

    # Should not create yellow alert when red alert exists
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should ignore completed and cancelled tasks when checking for duplicates" do
    patient = Patient.create!(
      first_name: "Completed",
      last_name: "Task",
      age: 30,
      mrn: "COMPLETED_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 25.minutes.ago
    )

    # Create a completed yellow alert task
    NursingTask.create!(
      patient: patient,
      task_type: :assessment,
      description: "WAIT TIME ALERT: #{patient.full_name} approaching ESI #{patient.esi_level} target",
      assigned_to: 'Charge RN',
      priority: :high,
      status: :completed, # This should be ignored
      due_at: 10.minutes.ago,
      room_number: patient.location_status.humanize
    )

    # Should create a new alert since the existing one is completed
    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    new_task = NursingTask.where(status: :pending).last
    assert_equal patient, new_task.patient
    assert_includes new_task.description, "WAIT TIME ALERT"
  end

  test "should use correct threshold calculations" do
    # ESI 4 target is 60 minutes
    # 75% threshold = 45 minutes
    # 100% threshold = 60 minutes
    
    # Patient at exactly 75% should trigger yellow alert
    patient_75 = Patient.create!(
      first_name: "Exactly",
      last_name: "SeventyFive",
      age: 30,
      mrn: "EXACT_75_#{SecureRandom.hex(4)}",
      esi_level: 4,
      location_status: :triage,
      arrival_time: 45.minutes.ago
    )

    # Patient just under 75% should not trigger alert
    patient_under_75 = Patient.create!(
      first_name: "Under",
      last_name: "SeventyFive",
      age: 30,
      mrn: "UNDER_75_#{SecureRandom.hex(4)}",
      esi_level: 4,
      location_status: :triage,
      arrival_time: 44.minutes.ago
    )

    # Should create exactly one alert (for the 75% patient)
    assert_difference "NursingTask.count", 1 do
      MonitorWaitTimesJob.perform_now
    end

    task = NursingTask.last
    assert_equal patient_75, task.patient
    assert_includes task.description, "WAIT TIME ALERT"
  end

  test "should handle edge cases in wait time calculations" do
    # Patient with very recent arrival time
    recent_patient = Patient.create!(
      first_name: "Recent",
      last_name: "Arrival",
      age: 30,
      mrn: "RECENT_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 1.minute.ago
    )

    # Should not create any alerts for recent patient
    assert_no_difference "NursingTask.count" do
      MonitorWaitTimesJob.perform_now
    end
  end

  test "should set correct due_at times for different alert types" do
    # Create patients that will trigger both yellow and red alerts
    yellow_patient = Patient.create!(
      first_name: "Yellow",
      last_name: "DueTime",
      age: 30,
      mrn: "YELLOW_DUE_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 25.minutes.ago
    )

    red_patient = Patient.create!(
      first_name: "Red",
      last_name: "DueTime",
      age: 35,
      mrn: "RED_DUE_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :triage,
      arrival_time: 15.minutes.ago
    )

    freeze_time do
      MonitorWaitTimesJob.perform_now

      yellow_task = NursingTask.where(patient: yellow_patient).first
      red_task = NursingTask.where(patient: red_patient).first

      # Yellow alert should be due in 10 minutes
      assert_equal 10.minutes.from_now.to_i, yellow_task.due_at.to_i

      # Red alert should be due in 5 minutes  
      assert_equal 5.minutes.from_now.to_i, red_task.due_at.to_i
    end
  end
end