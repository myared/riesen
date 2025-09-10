class CarePathwayProcedure < ApplicationRecord
  belongs_to :care_pathway
  
  # Common ED procedures
  PROCEDURES = [
    'IV Access Placement',
    'Foley Catheter Insertion',
    'Nasogastric Tube Placement',
    'Central Line Placement',
    'Arterial Line Placement',
    'Lumbar Puncture',
    'Paracentesis',
    'Thoracentesis',
    'Wound Closure/Suturing',
    'Wound Irrigation and Debridement',
    'Splint Application',
    'Cast Application',
    'Joint Reduction',
    'Incision and Drainage',
    'Foreign Body Removal',
    'Cardioversion',
    'Intubation',
    'Chest Tube Placement',
    'Procedural Sedation',
    'Point of Care Ultrasound'
  ].freeze
  
  validates :name, presence: true
  
  scope :pending, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }
  
  # Mark procedure as complete
  def complete!(user_name = nil)
    update!(
      completed: true,
      completed_at: Time.current,
      completed_by: user_name || 'System'
    )
  end
  
  # Get status
  def status
    completed? ? 'Complete' : 'Pending'
  end
  
  # Get status class for styling
  def status_class
    completed? ? 'procedure-completed' : 'procedure-pending'
  end
  
  # Get procedure icon
  def icon
    '🔧'
  end
end