class NursingTask < ApplicationRecord
  # Constants
  OVERDUE_THRESHOLD_MINUTES = 15
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
  scope :overdue, -> {
    where("started_at < ? AND status = ?", OVERDUE_THRESHOLD_MINUTES.minutes.ago, statuses[:pending])
  }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :for_nurse, ->(nurse_type) { where(assigned_to: nurse_type) }

  # Create room assignment task when triage is completed
  def self.create_room_assignment_task(patient)
    nurse_type = patient.rp_eligible? ? "RP RN" : "ED RN"

    create!(
      patient: patient,
      task_type: :room_assignment,
      description: "Transport #{patient.full_name} to #{patient.rp_eligible? ? 'RP' : 'ED'} area",
      assigned_to: nurse_type,
      priority: patient.esi_level <= 2 ? :urgent : :high,
      status: :pending,
      started_at: Time.current  # Track when task started instead of due_at
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

  # Check if task is severely overdue (more than threshold)
  def severely_overdue?
    return false unless started_at && status_pending?
    elapsed_time > OVERDUE_THRESHOLD_MINUTES
  end

  # Time elapsed since task started (in minutes)
  def elapsed_time
    return 0 unless started_at
    ((Time.current - started_at) / 60).round
  end

  # For backward compatibility
  def overdue?
    severely_overdue?
  end

  # For backward compatibility - now returns elapsed time
  def time_remaining
    elapsed_time
  end

  # For backward compatibility
  def minutes_overdue
    return 0 unless severely_overdue?
    elapsed_time - OVERDUE_THRESHOLD_MINUTES  # Minutes past the threshold
  end

  # Calculate timer status based on elapsed time
  def timer_status
    # Use different thresholds based on task type
    thresholds = task_type_medication? ? [ 5, 10 ] : [ 20, 40 ]

    if elapsed_time <= thresholds[0]
      "green"
    elsif elapsed_time <= thresholds[1]
      "yellow"
    else
      "red"
    end
  end

  # Get CSS class for priority
  def priority_class
    # Use timer-based coloring
    "timer-#{timer_status}"
  end

  # Numeric priority for sorting (higher = more urgent)
  def sort_priority
    case timer_status
    when "red" then 3
    when "yellow" then 2
    when "green" then 1
    else 0
    end
  end
end
