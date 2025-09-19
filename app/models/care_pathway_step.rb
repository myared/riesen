class CarePathwayStep < ApplicationRecord
  belongs_to :care_pathway
  
  # Step names for triage pathway
  TRIAGE_STEPS = {
    check_in: 'Check-In',
    intake: 'Intake',
    bed_assignment: 'Bed Assignment',
    pending_transfer: 'Pending Transfer'
  }.freeze
  
  validates :name, presence: true
  validates :sequence, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  scope :ordered, -> { order(:sequence) }
  scope :completed, -> { where(completed: true) }
  scope :pending, -> { where(completed: false) }
  
  # Check if this is the current active step
  def current?
    return false if completed?
    
    # It's current if all previous steps are completed
    care_pathway.care_pathway_steps
                .where('sequence < ?', sequence)
                .where(completed: false)
                .none?
  end
  
  # Mark step as complete
  def complete!(user_name = nil)
    update!(
      completed: true,
      completed_at: Time.current,
      completed_by: user_name || 'System'
    )
  end
  
  # Get step status
  def status
    if completed?
      'completed'
    elsif current?
      'in_progress'
    else
      'pending'
    end
  end
  
  # Get step icon based on status
  def status_icon
    case status
    when 'completed'
      '✓'
    when 'in_progress'
      '○'
    else
      '○'
    end
  end
  
  # Get status color class
  def status_class
    case status
    when 'completed'
      'step-completed'
    when 'in_progress'
      'step-current'
    else
      'step-pending'
    end
  end
end