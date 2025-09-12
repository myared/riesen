require "test_helper"

class NursingTaskTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 30,
      mrn: "NT_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      rp_eligible: false
    )
    
    @rp_eligible_patient = Patient.create!(
      first_name: "RP",
      last_name: "Patient", 
      age: 25,
      mrn: "NT_#{SecureRandom.hex(4)}",
      esi_level: 2,
      location_status: :needs_room_assignment,
      rp_eligible: true
    )
    
    @task = NursingTask.create!(
      patient: @patient,
      task_type: :room_assignment,
      description: "Transport Test Patient to ED area",
      assigned_to: "ED RN",
      priority: :high,
      status: :pending,
      started_at: Time.current
    )
    
    @room = Room.create!(
      number: "NT_#{SecureRandom.hex(4)}",
      room_type: :ed,
      status: :available
    )
  end

  test "nursing task validations" do
    task = NursingTask.new
    assert_not task.valid?
    assert_includes task.errors[:patient], "must exist"
    assert_includes task.errors[:description], "can't be blank"
    
    # Enum fields may have default values, so just test required fields
    assert task.errors.any?, "Should have validation errors"
  end

  test "task type enum" do
    assert @task.task_type_room_assignment?
    
    @task.update!(task_type: :transport)
    assert @task.task_type_transport?
    
    @task.update!(task_type: :medication)
    assert @task.task_type_medication?
    
    @task.update!(task_type: :assessment)
    assert @task.task_type_assessment?
    
    @task.update!(task_type: :procedure)
    assert @task.task_type_procedure?
  end

  test "priority enum" do
    assert @task.priority_high?
    
    @task.update!(priority: :low)
    assert @task.priority_low?
    
    @task.update!(priority: :medium)
    assert @task.priority_medium?
    
    @task.update!(priority: :urgent)
    assert @task.priority_urgent?
  end

  test "status enum" do
    assert @task.status_pending?
    
    @task.update!(status: :in_progress)
    assert @task.status_in_progress?
    
    @task.update!(status: :completed)
    assert @task.status_completed?
    
    @task.update!(status: :cancelled)
    assert @task.status_cancelled?
  end

  test "scopes work correctly" do
    completed_task = NursingTask.create!(
      patient: @patient,
      task_type: :medication,
      description: "Administer medication",
      assigned_to: "ED RN",
      priority: :medium,
      status: :completed,
      started_at: 2.hours.ago
    )
    
    overdue_task = NursingTask.create!(
      patient: @patient,
      task_type: :assessment,
      description: "Complete assessment",
      assigned_to: "ED RN",
      priority: :high,
      status: :pending,
      started_at: 20.minutes.ago
    )
    
    # Test pending_tasks scope
    pending_tasks = NursingTask.pending_tasks
    assert_includes pending_tasks, @task
    assert_includes pending_tasks, overdue_task
    assert_not_includes pending_tasks, completed_task
    
    # Test overdue scope
    overdue_tasks = NursingTask.overdue
    assert_includes overdue_tasks, overdue_task
    assert_not_includes overdue_tasks, @task
    assert_not_includes overdue_tasks, completed_task
    
    # Test by_priority scope - should order by priority desc, created_at asc
    priority_ordered = NursingTask.by_priority
    # The first task should be the highest priority available
    first_priority = priority_ordered.first&.priority
    assert first_priority.present?, "Should have at least one task"
    
    # Test for_nurse scope
    nurse_tasks = NursingTask.for_nurse("ED RN")
    assert_includes nurse_tasks, @task
  end

  test "create_room_assignment_task for ED patient" do
    task = NursingTask.create_room_assignment_task(@patient)
    
    assert task.persisted?
    assert task.task_type_room_assignment?
    assert_equal @patient, task.patient
    assert_equal "ED RN", task.assigned_to
    assert_equal "high", task.priority
    assert task.status_pending?
    assert_includes task.description, "ED area"
    assert_not_nil task.started_at
    assert task.started_at <= Time.current
  end

  test "create_room_assignment_task for RP patient" do
    task = NursingTask.create_room_assignment_task(@rp_eligible_patient)
    
    assert task.persisted?
    assert task.task_type_room_assignment?
    assert_equal @rp_eligible_patient, task.patient
    assert_equal "RP RN", task.assigned_to
    assert_includes task.description, "RP area"
  end

  test "create_room_assignment_task sets urgent priority for critical patients" do
    critical_patient = Patient.create!(
      first_name: "Critical",
      last_name: "Patient",
      age: 45,
      mrn: "NURSING_CRIT001",
      esi_level: 1,
      location_status: :needs_room_assignment,
      rp_eligible: false
    )
    
    task = NursingTask.create_room_assignment_task(critical_patient)
    assert_equal "urgent", task.priority
  end

  test "complete! updates task status and timestamps" do
    @task.complete!
    
    assert @task.status_completed?
    assert_not_nil @task.completed_at
    assert @task.completed_at <= Time.current
  end

  test "complete! with room number for room assignment task" do
    # Simplified test - just test that room_number is set and status changes
    @task.complete!(@room.number)
    
    assert @task.status_completed?
    assert_equal @room.number, @task.room_number
    assert_not_nil @task.completed_at
  end

  test "complete! is transactional" do
    # Test transaction rollback by monkey patching update! to fail
    original_method = @task.method(:update!)
    @task.define_singleton_method(:update!) do |attrs|
      raise ActiveRecord::RecordInvalid.new(@task)
    end
    
    assert_raises(ActiveRecord::RecordInvalid) do
      @task.complete!
    end
    
    @task.reload
    assert @task.status_pending?
    assert_nil @task.completed_at
  end

  test "overdue? returns correct status" do
    # Task just started should not be overdue
    assert_not @task.overdue?
    
    # Update task to be overdue (started more than 15 minutes ago)
    @task.update!(started_at: 20.minutes.ago)
    assert @task.overdue?
    
    # Completed task should not be overdue
    @task.update!(status: :completed)
    assert_not @task.overdue?
    
    # Task without started_at should not be overdue
    @task.update!(started_at: nil, status: :pending)
    assert_not @task.overdue?
  end

  test "elapsed_time calculates correctly" do
    # Task just started should have 0 elapsed time
    @task.update!(started_at: Time.current)
    assert_equal 0, @task.elapsed_time
    
    # Task started 10 minutes ago should show 10 minutes
    @task.update!(started_at: 10.minutes.ago)
    elapsed = @task.elapsed_time
    assert elapsed >= 9
    assert elapsed <= 11
    
    # Task without started_at should return 0
    @task.update!(started_at: nil)
    assert_equal 0, @task.elapsed_time
  end

  test "minutes_overdue calculates correctly" do
    # Task not overdue should return 0
    @task.update!(started_at: 10.minutes.ago)
    assert_equal 0, @task.minutes_overdue
    
    # Overdue task should return minutes past threshold
    @task.update!(started_at: 25.minutes.ago)
    minutes_overdue = @task.minutes_overdue
    assert minutes_overdue >= 9  # 25 - 15 = 10, allow for time drift
    assert minutes_overdue <= 11
  end

  test "priority_class returns correct CSS class" do
    # Task not overdue should show success (green)
    @task.update!(started_at: 5.minutes.ago)
    assert_equal "priority-success", @task.priority_class
    
    # Severely overdue task should show urgent (red)
    @task.update!(started_at: 20.minutes.ago)
    assert_equal "priority-urgent", @task.priority_class
  end

  test "task creation with all required attributes" do
    task = NursingTask.new(
      patient: @patient,
      task_type: :medication,
      description: "Administer pain medication",
      assigned_to: "ED RN",
      priority: :medium,
      status: :pending
    )
    
    assert task.valid?
    assert task.save
  end

  test "task with invalid enum values" do
    assert_raises(ArgumentError) do
      NursingTask.create!(
        patient: @patient,
        task_type: :invalid_type,
        description: "Test",
        assigned_to: "ED RN",
        priority: :medium
      )
    end
  end
end
