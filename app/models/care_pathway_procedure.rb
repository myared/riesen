class CarePathwayProcedure < ApplicationRecord
  belongs_to :care_pathway

  # Common ED procedures
  PROCEDURES = [
    "IV Access Placement",
    "Foley Catheter Insertion",
    "Nasogastric Tube Placement",
    "Central Line Placement",
    "Arterial Line Placement",
    "Lumbar Puncture",
    "Paracentesis",
    "Thoracentesis",
    "Wound Closure/Suturing",
    "Wound Irrigation and Debridement",
    "Splint Application",
    "Cast Application",
    "Joint Reduction",
    "Incision and Drainage",
    "Foreign Body Removal",
    "Cardioversion",
    "Intubation",
    "Chest Tube Placement",
    "Procedural Sedation",
    "Point of Care Ultrasound"
  ].freeze

  validates :name, presence: true

  scope :pending, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }
  scope :ordered, -> { where(ordered: true) }
  scope :not_ordered, -> { where(ordered: false) }

  # Mark procedure as ordered
  def order!(user_name = nil)
    update!(
      ordered: true,
      ordered_at: Time.current,
      ordered_by: user_name || "System"
    )
  end

  # Mark procedure as complete
  def complete!(user_name = nil)
    update!(
      completed: true,
      completed_at: Time.current,
      completed_by: user_name || "System"
    )
  end

  # Get status
  def status
    if completed?
      "Complete"
    elsif ordered?
      "Ordered"
    else
      "Pending"
    end
  end

  # Get status class for styling
  def status_class
    if completed?
      "procedure-completed"
    elsif ordered?
      "procedure-ordered"
    else
      "procedure-pending"
    end
  end

  # Can advance to next state?
  def can_advance?
    !completed?
  end

  # Advance to next state
  def advance_status!(user_name = nil)
    if !ordered?
      order!(user_name)
    elsif !completed?
      complete!(user_name)
    else
      false
    end
  end

  # Get next status label
  def next_status_label
    if !ordered?
      "Ordered"
    elsif !completed?
      "Completed"
    else
      nil
    end
  end

  # Check if can be completed (must be ordered first)
  def can_complete?
    ordered? && !completed?
  end

  # Get procedure icon
  def icon
    "🔧"
  end
end
