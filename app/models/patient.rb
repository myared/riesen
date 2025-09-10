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
  
  # Enum for location status
  enum :location_status, {
    waiting_room: 0,
    triage: 1,
    results_pending: 2,
    ed_room: 3,
    treatment: 4,
    discharged: 5
  }, prefix: :location
  
  has_many :vitals, dependent: :destroy
  has_many :events, dependent: :destroy
  
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
  
  def full_name
    "#{first_name} #{last_name}"
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
  
  def critical?
    esi_level.in?([1, 2])
  end
end
