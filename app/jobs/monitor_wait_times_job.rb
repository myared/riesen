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
    return unless patient.esi_level.present?

    # Calculate ESI-based thresholds
    target = patient.esi_target_minutes

    # ESI 1 is always critical immediately
    if patient.esi_level == 1 && wait_minutes > 0
      # Check for existing alert
      existing_task = NursingTask.where(
        patient: patient,
        task_type: :assessment,
        status: [:pending, :in_progress]
      ).where("description LIKE ?", "CRITICAL WAIT TIME: %").first

      unless existing_task
        NursingTask.create!(
          patient: patient,
          task_type: :assessment,
          description: "CRITICAL WAIT TIME: ESI1 Critical - #{patient.full_name}",
          assigned_to: 'Charge RN',
          priority: :urgent,
          status: :pending,
          due_at: Time.current,
          room_number: patient.location_status.humanize
        )
      end
      return
    end

    # For other ESI levels, use percentage-based thresholds
    yellow_threshold = (target * 0.75).round
    red_threshold = target

    # Check for existing alerts (match any WAIT TIME ALERT or CRITICAL WAIT TIME for this patient)
    existing_yellow_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      status: [:pending, :in_progress]
    ).where("description LIKE ?", "WAIT TIME ALERT: %").first

    existing_red_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      status: [:pending, :in_progress]
    ).where("description LIKE ?", "CRITICAL WAIT TIME: %").first

    # Create tasks based on wait time thresholds
    if wait_minutes >= red_threshold && !existing_red_task
      # Red: Exceeds 100% of ESI target
      NursingTask.create!(
        patient: patient,
        task_type: :assessment,
        description: "CRITICAL WAIT TIME: #{patient.full_name} (ESI #{patient.esi_level}) waiting #{wait_minutes} minutes",
        assigned_to: 'Charge RN',
        priority: :urgent,
        status: :pending,
        due_at: 5.minutes.from_now,
        room_number: patient.location_status.humanize
      )
    elsif wait_minutes >= yellow_threshold && wait_minutes < red_threshold && !existing_yellow_task && !existing_red_task
      # Yellow: Between 75% and 100% of ESI target
      NursingTask.create!(
        patient: patient,
        task_type: :assessment,
        description: "WAIT TIME ALERT: #{patient.full_name} (ESI #{patient.esi_level}) waiting #{wait_minutes} minutes",
        assigned_to: 'Charge RN',
        priority: :high,
        status: :pending,
        due_at: 10.minutes.from_now,
        room_number: patient.location_status.humanize
      )
    end
    # Note: No green tasks are created - only yellow and red alerts
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