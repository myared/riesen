class MonitorWaitTimesJob < ApplicationJob
  queue_as :default
  
  def perform
    Patient.in_triage.each do |patient|
      check_and_create_wait_time_alerts(patient)
    end
    
    Patient.location_needs_room_assignment.each do |patient|
      check_and_create_room_assignment_alerts(patient)
    end
    
    self.class.set(wait: 30.seconds).perform_later
  end
  
  private
  
  def check_and_create_wait_time_alerts(patient)
    wait_minutes = patient.wait_time_minutes
    return unless wait_minutes.present?

    # Hardcoded thresholds for three-color system
    yellow_threshold = 45  # minutes - approaching due time
    red_threshold = 60     # minutes - fully due
    critical_threshold = 80  # minutes - over 20 minutes due (60 + 20)

    # Check for existing tasks of each color
    existing_green_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      description: "WAIT TIME STATUS: #{patient.full_name} is on track (green)",
      status: [:pending, :in_progress]
    ).first

    existing_yellow_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      description: "WAIT TIME ALERT: #{patient.full_name} is overdue (yellow)",
      status: [:pending, :in_progress]
    ).first

    existing_red_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      description: "CRITICAL WAIT TIME: #{patient.full_name} is critically overdue (red)",
      status: [:pending, :in_progress]
    ).first

    # Create tasks based on wait time - prioritize red over yellow over green
    if wait_minutes >= critical_threshold && !existing_red_task
      # Red: Over 20 minutes due (80+ minutes)
      NursingTask.create!(
        patient: patient,
        task_type: :assessment,
        description: "CRITICAL WAIT TIME: #{patient.full_name} is critically overdue (red)",
        assigned_to: 'Charge RN',
        priority: :urgent,
        status: :pending,
        due_at: 5.minutes.from_now,
        room_number: patient.location_status.humanize
      )
    elsif wait_minutes >= yellow_threshold && wait_minutes < critical_threshold && !existing_yellow_task && !existing_red_task
      # Yellow: Overdue (45-79 minutes)
      NursingTask.create!(
        patient: patient,
        task_type: :assessment,
        description: "WAIT TIME ALERT: #{patient.full_name} is overdue (yellow)",
        assigned_to: 'Charge RN',
        priority: :high,
        status: :pending,
        due_at: 10.minutes.from_now,
        room_number: patient.location_status.humanize
      )
    elsif wait_minutes < yellow_threshold && !existing_green_task && !existing_yellow_task && !existing_red_task
      # Green: Not yet due (under 45 minutes)
      NursingTask.create!(
        patient: patient,
        task_type: :assessment,
        description: "WAIT TIME STATUS: #{patient.full_name} is on track (green)",
        assigned_to: 'Charge RN',
        priority: :low,
        status: :pending,
        due_at: 15.minutes.from_now,
        room_number: patient.location_status.humanize
      )
    end
  end
  
  def check_and_create_room_assignment_alerts(patient)
    return unless patient.room_assignment_needed_at.present?
    
    minutes_waiting = ((Time.current - patient.room_assignment_needed_at) / 60).round
    
    yellow_threshold = 15
    red_threshold = 20
    
    existing_yellow_task = NursingTask.where(
      patient: patient,
      task_type: :room_assignment,
      description: "ROOM ASSIGNMENT DELAYED: #{patient.full_name} waiting #{minutes_waiting} minutes",
      status: [:pending, :in_progress]
    ).first
    
    existing_red_task = NursingTask.where(
      patient: patient,
      task_type: :room_assignment,
      description: "CRITICAL ROOM DELAY: #{patient.full_name} waiting #{minutes_waiting} minutes",
      status: [:pending, :in_progress]
    ).first
    
    if minutes_waiting >= red_threshold && !existing_red_task
      NursingTask.create!(
        patient: patient,
        task_type: :room_assignment,
        description: "CRITICAL ROOM DELAY: #{patient.full_name} waiting #{minutes_waiting} minutes",
        assigned_to: 'Charge RN',
        priority: :urgent,
        status: :pending,
        due_at: Time.current,
        room_number: "Awaiting Room"
      )
    elsif minutes_waiting >= yellow_threshold && minutes_waiting < red_threshold && !existing_yellow_task && !existing_red_task
      NursingTask.create!(
        patient: patient,
        task_type: :room_assignment,
        description: "ROOM ASSIGNMENT DELAYED: #{patient.full_name} waiting #{minutes_waiting} minutes",
        assigned_to: 'Charge RN',
        priority: :high,
        status: :pending,
        due_at: 5.minutes.from_now,
        room_number: "Awaiting Room"
      )
    end
  end
end