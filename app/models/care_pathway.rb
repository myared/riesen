class CarePathway < ApplicationRecord
  belongs_to :patient
  has_many :care_pathway_steps, dependent: :destroy
  has_many :care_pathway_orders, dependent: :destroy
  has_many :care_pathway_procedures, dependent: :destroy
  has_many :care_pathway_clinical_endpoints, dependent: :destroy
  
  # Pathway types
  enum :pathway_type, {
    triage: 0,
    emergency_room: 1,
    results_pending: 2
  }, prefix: true
  
  # Status
  enum :status, {
    not_started: 0,
    in_progress: 1,
    completed: 2
  }, prefix: true
  
  validates :pathway_type, presence: true
  validates :patient_id, presence: true
  
  # Calculate overall progress percentage
  def progress_percentage
    if pathway_type_triage?
      calculate_triage_progress
    elsif pathway_type_emergency_room?
      calculate_emergency_room_progress
    else
      0
    end
  end
  
  # Get current step for triage pathway
  def current_triage_step
    return nil unless pathway_type_triage?
    care_pathway_steps.where(completed: false).order(:sequence).first
  end
  
  # Get all completed steps
  def completed_steps
    care_pathway_steps.where(completed: true)
  end
  
  # Complete a specific step
  def complete_step(step_name)
    step = care_pathway_steps.find_by(name: step_name)
    return false unless step
    
    step.update(
      completed: true,
      completed_at: Time.current,
      completed_by: Current.user&.name # Assuming you have Current.user set
    )
  end
  
  # Check if pathway is complete
  def complete?
    if pathway_type_triage?
      care_pathway_steps.where(completed: false).none?
    elsif pathway_type_emergency_room?
      # Check if all required items are completed
      all_orders_complete? && all_procedures_complete? && all_endpoints_achieved?
    else
      false
    end
  end
  
  private
  
  def calculate_triage_progress
    total_steps = care_pathway_steps.count
    return 0 if total_steps.zero?
    
    completed = care_pathway_steps.where(completed: true).count
    (completed.to_f / total_steps * 100).round
  end
  
  def calculate_emergency_room_progress
    total_items = care_pathway_orders.count +
                  care_pathway_procedures.count +
                  care_pathway_clinical_endpoints.count

    return 0 if total_items.zero?

    completed_items = care_pathway_orders.completed.count +
                      care_pathway_procedures.where(completed: true).count +
                      care_pathway_clinical_endpoints.where(achieved: true).count

    (completed_items.to_f / total_items * 100).round
  end
  
  def all_orders_complete?
    care_pathway_orders.pending.none?
  end
  
  def all_procedures_complete?
    care_pathway_procedures.where(completed: false).none?
  end
  
  def all_endpoints_achieved?
    care_pathway_clinical_endpoints.where(achieved: false).none?
  end
end