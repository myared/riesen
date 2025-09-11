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
    return unless patient.esi_level.present?
    
    target_minutes = patient.esi_target_minutes
    wait_minutes = patient.wait_time_minutes
    
    yellow_threshold = target_minutes * 0.75
    red_threshold = target_minutes
    
    existing_yellow_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      description: "WAIT TIME ALERT: #{patient.full_name} approaching ESI #{patient.esi_level} target",
      status: [:pending, :in_progress]
    ).first
    
    existing_red_task = NursingTask.where(
      patient: patient,
      task_type: :assessment,
      description: "CRITICAL WAIT TIME: #{patient.full_name} exceeded ESI #{patient.esi_level} target",
      status: [:pending, :in_progress]
    ).first
    
    if wait_minutes >= red_threshold && !existing_red_task
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
    elsif wait_minutes >= yellow_threshold && wait_minutes < red_threshold && !existing_yellow_task && !existing_red_task
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