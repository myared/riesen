class NursingTask < ApplicationRecord
  belongs_to :patient
  
  # Task types
  enum :task_type, {
    room_assignment: 0,
    transport: 1,
    medication: 2,
    assessment: 3,
    procedure: 4
  }, prefix: true
  
  # Task priorities
  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, prefix: true
  
  # Task statuses
  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    cancelled: 3
  }, prefix: true
  
  validates :task_type, presence: true
  validates :description, presence: true
  validates :priority, presence: true
  
  scope :pending_tasks, -> { status_pending }
  scope :overdue, -> { where('due_at < ?', Time.current).status_pending }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :for_nurse, ->(nurse_type) { where(assigned_to: nurse_type) }
  
  # Create room assignment task when triage is completed
  def self.create_room_assignment_task(patient)
    nurse_type = patient.rp_eligible? ? 'RP RN' : 'ED RN'
    
    create!(
      patient: patient,
      task_type: :room_assignment,
      description: "Transport #{patient.full_name} to #{patient.rp_eligible? ? 'RP' : 'ED'} area",
      assigned_to: nurse_type,
      priority: patient.esi_level <= 2 ? :urgent : :high,
      status: :pending,
      due_at: 20.minutes.from_now
    )
  end
  
  # Complete the task
  def complete!(room_number = nil)
    transaction do
      update!(
        status: :completed,
        completed_at: Time.current,
        room_number: room_number
      )
      
      # If this is a room assignment task, assign the room
      if task_type_room_assignment? && room_number
        room = Room.find_by(number: room_number)
        room&.assign_patient(patient)
      end
    end
  end
  
  # Check if task is overdue
  def overdue?
    due_at && due_at < Time.current && status_pending?
  end
  
  # Time remaining until due
  def time_remaining
    return nil unless due_at
    return 0 if overdue?
    
    ((due_at - Time.current) / 60).round # in minutes
  end
  
  # Minutes overdue
  def minutes_overdue
    return 0 unless overdue?
    
    ((Time.current - due_at) / 60).round
  end
  
  # Get CSS class for priority
  def priority_class
    case priority
    when 'urgent' then 'priority-urgent'
    when 'high' then 'priority-high'
    when 'medium' then 'priority-medium'
    else 'priority-low'
    end
  end
end