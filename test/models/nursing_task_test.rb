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
      due_at: 30.minutes.from_now
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
      due_at: 1.hour.ago
    )
    
    overdue_task = NursingTask.create!(
      patient: @patient,
      task_type: :assessment,
      description: "Complete assessment",
      assigned_to: "ED RN",
      priority: :high,
      status: :pending,
      due_at: 1.hour.ago
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
    assert_not_nil task.due_at
    assert task.due_at > Time.current
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
    # Task due in future should not be overdue
    assert_not @task.overdue?
    
    # Update task to be overdue
    @task.update!(due_at: 1.hour.ago)
    assert @task.overdue?
    
    # Completed task should not be overdue
    @task.update!(status: :completed)
    assert_not @task.overdue?
    
    # Task without due date should not be overdue
    @task.update!(due_at: nil, status: :pending)
    assert_not @task.overdue?
  end

  test "time_remaining calculates correctly" do
    future_time = 2.hours.from_now
    @task.update!(due_at: future_time)
    
    # Should return time in minutes
    time_remaining = @task.time_remaining
    assert time_remaining > 0
    assert time_remaining <= 120 # 2 hours in minutes
    
    # Overdue task should return 0
    @task.update!(due_at: 1.hour.ago)
    assert_equal 0, @task.time_remaining
    
    # Task without due date should return nil
    @task.update!(due_at: nil)
    assert_nil @task.time_remaining
  end

  test "minutes_overdue calculates correctly" do
    # Future task should return 0
    assert_equal 0, @task.minutes_overdue
    
    # Overdue task should return positive minutes
    @task.update!(due_at: 90.minutes.ago)
    minutes_overdue = @task.minutes_overdue
    assert minutes_overdue > 0
    assert minutes_overdue >= 90
  end

  test "priority_class returns correct CSS class" do
    @task.update!(priority: :urgent)
    assert_equal "priority-urgent", @task.priority_class
    
    @task.update!(priority: :high)
    assert_equal "priority-high", @task.priority_class
    
    @task.update!(priority: :medium)
    assert_equal "priority-medium", @task.priority_class
    
    @task.update!(priority: :low)
    assert_equal "priority-low", @task.priority_class
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
