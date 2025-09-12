class Patient < ApplicationRecord
  # Constants for ESI level wait time targets (in minutes)
  ESI_WAIT_TARGETS = {
    1 => 0,    # Resuscitation - Immediate
    2 => 10,   # Emergent - 10 minutes
    3 => 30,   # Urgent - 30 minutes
    4 => 60,   # Less Urgent - 60 minutes
    5 => 120   # Non-Urgent - 120 minutes
  }.freeze
  
  # ESI Level descriptions
  ESI_DESCRIPTIONS = {
    1 => 'Resuscitation',
    2 => 'Emergent',
    3 => 'Urgent',
    4 => 'Less Urgent',
    5 => 'Non-Urgent'
  }.freeze
  
  # Valid pain score range
  PAIN_SCORE_RANGE = (1..10).freeze
  
  # Timer thresholds (in minutes)
  ROOM_ASSIGNMENT_TARGET = 20   # Target time for room assignment
  TIMER_WARNING_THRESHOLD = 20  # When timer turns yellow
  TIMER_CRITICAL_THRESHOLD = 40 # When timer turns red
  TIMER_MAX_DISPLAY = 60        # Max value for progress bar
  
  # Enum for location status
  enum :location_status, {
    waiting_room: 0,
    triage: 1,
    needs_room_assignment: 2,
    results_pending: 3,
    ed_room: 4,
    treatment: 5,
    discharged: 6
  }, prefix: :location
  
  has_many :vitals, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :care_pathways, dependent: :destroy
  
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :mrn, presence: true, uniqueness: true
  validates :esi_level, inclusion: { in: ESI_WAIT_TARGETS.keys }, allow_nil: true
  validates :pain_score, inclusion: { in: PAIN_SCORE_RANGE }, allow_nil: true
  
  # Scopes
  scope :waiting, -> { location_waiting_room }
  scope :in_triage, -> { where(location_status: [:waiting_room, :triage]) }
  scope :in_ed, -> { where(location_status: [:ed_room, :treatment]) }
  scope :with_provider, -> { where.not(provider: nil) }
  scope :critical, -> { where(esi_level: [1, 2]) }
  
  # New scopes for dashboard organization
  scope :by_arrival_time, -> { order(arrival_time: :asc) }
  
  scope :by_priority_time, -> {
    needs_room_status = location_statuses[:needs_room_assignment]
    order(
      Arel.sql(
        "CASE 
          WHEN location_status = #{connection.quote(needs_room_status)} 
          THEN COALESCE(triage_completed_at, arrival_time)
          ELSE arrival_time
        END ASC"
      )
    )
  }
  
  scope :needs_rp_assignment, -> {
    where(location_status: :needs_room_assignment, rp_eligible: true)
  }
  
  scope :needs_ed_assignment, -> {
    where(location_status: :needs_room_assignment, rp_eligible: false)
  }
  
  scope :in_results_pending, -> {
    where(location_status: :results_pending)
  }
  
  scope :in_ed_treatment, -> {
    where(location_status: [:ed_room, :treatment])
  }
  
  def full_name
    "#{first_name} #{last_name}"
  end
  
  def active_care_pathway
    # Determine the expected pathway type based on location
    expected_type = case location_status
                   when 'waiting_room', 'triage'
                     'triage'
                   when 'needs_room_assignment', 'results_pending', 'ed_room', 'treatment'
                     'emergency_room'
                   else
                     'triage'
                   end
    
    # Return the most recent active pathway of the expected type
    care_pathways.where(
      pathway_type: expected_type,
      status: [:not_started, :in_progress]
    ).order(created_at: :desc).first
  end
  
  def latest_vital
    vitals.order(recorded_at: :desc).first
  end
  
  def wait_progress_percentage
    target = esi_target_minutes
    return 100 if target.zero?
    [(wait_time_minutes.to_f / target * 100).round, 100].min
  end
  
  def esi_target_minutes
    ESI_WAIT_TARGETS[esi_level] || 30
  end
  
  def esi_target_label
    return "Immediate" if esi_level == 1
    "#{esi_target_minutes}m target"
  end
  
  def esi_description
    ESI_DESCRIPTIONS[esi_level]
  end
  
  def overdue?
    wait_time_minutes > esi_target_minutes
  end
  
  def wait_status
    return :on_time if wait_time_minutes <= esi_target_minutes
    
    over_target = wait_time_minutes - esi_target_minutes
    over_percentage = (over_target.to_f / esi_target_minutes * 100).round
    
    if over_percentage <= 50
      :warning
    else
      :critical
    end
  end
  
  def wait_status_class
    case wait_status
    when :warning
      'wait-warning'
    when :critical
      'wait-critical'
    else
      ''
    end
  end
  
  def critical?
    esi_level.in?([1, 2])
  end
  
  def location_needs_room_assignment?
    location_status == 'needs_room_assignment'
  end
  
  def wait_time_minutes
    return 0 unless arrival_time
    ((Time.current - arrival_time) / 60).round
  end
  
  def room_assignment_started_at
    return nil unless location_needs_room_assignment?
    triage_completed_at || updated_at
  end
  
  def time_waiting_for_room
    return 0 unless room_assignment_started_at
    ((Time.current - room_assignment_started_at) / 60).round
  end
end
