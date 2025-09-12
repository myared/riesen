class CarePathwayOrder < ApplicationRecord
  belongs_to :care_pathway

  # Order types
  enum :order_type, {
    lab: 0,
    medication: 1,
    imaging: 2
  }, prefix: true

  # Order status progression
  enum :status, {
    ordered: 0,
    collected: 1,
    in_lab: 2,
    resulted: 3
  }, prefix: false

  # Common lab orders
  LAB_ORDERS = [
    "CBC with Differential",
    "Basic Metabolic Panel",
    "Comprehensive Metabolic Panel",
    "Liver Function Tests",
    "Lipid Panel",
    "PT/INR",
    "PTT",
    "Troponin",
    "BNP",
    "D-Dimer",
    "Urinalysis",
    "Urine Culture",
    "Blood Culture",
    "Lactate",
    "Arterial Blood Gas",
    "COVID-19 PCR",
    "Rapid Strep",
    "Influenza A/B"
  ].freeze

  # Common medications
  MEDICATIONS = [
    "Acetaminophen 650mg PO",
    "Ibuprofen 400mg PO",
    "Morphine 2mg IV",
    "Zofran 4mg IV",
    "Normal Saline 1L IV",
    "Ceftriaxone 1g IV",
    "Azithromycin 500mg PO",
    "Prednisone 40mg PO",
    "Albuterol Nebulizer",
    "Epinephrine 0.3mg IM",
    "Nitroglycerin 0.4mg SL",
    "Aspirin 325mg PO",
    "Heparin 5000 units SC",
    "Lorazepam 1mg IV"
  ].freeze

  # Common imaging orders
  IMAGING_ORDERS = [
    "Chest X-Ray",
    "Abdominal X-Ray",
    "CT Head without Contrast",
    "CT Chest with PE Protocol",
    "CT Abdomen/Pelvis with Contrast",
    "MRI Brain",
    "Ultrasound Abdomen",
    "Ultrasound Lower Extremity DVT",
    "Echocardiogram",
    "EKG"
  ].freeze

  validates :name, presence: true
  validates :order_type, presence: true
  validates :status, presence: true
  validates :timer_status, inclusion: { in: %w[green yellow red] }, allow_nil: true
  validates :last_status_duration_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Default ordering - alphabetical by name
  default_scope { order(:name) }

  scope :labs, -> { order_type_lab }
  scope :medications, -> { order_type_medication }
  scope :imaging, -> { order_type_imaging }
  scope :pending, -> { where.not(status: :resulted) }
  scope :completed, -> { where(status: :resulted) }

  # Progress to next status
  def advance_status!(user_name = nil)
    return false if resulted?

    transaction do
      # Use lock to prevent concurrent updates
      lock!

      previous_timestamp = get_previous_timestamp
      current_time = Time.current

      # Calculate duration for timer status
      if previous_timestamp
        duration_minutes = ((current_time - previous_timestamp) / 60).round
        timer_status = calculate_timer_status(duration_minutes)
      else
        duration_minutes = 0
        timer_status = "green"
      end

      next_status = case status.to_sym
      when :ordered then :collected
      when :collected then :in_lab
      when :in_lab then :resulted
      else
                      return false
      end

      # Set the appropriate timestamp based on the new status
      timestamp_updates = {
        status: next_status,
        status_updated_at: current_time,
        status_updated_by: user_name || "System",
        last_status_duration_minutes: duration_minutes,
        timer_status: timer_status
      }

      case next_status
      when :collected
        timestamp_updates[:collected_at] = current_time
      when :in_lab
        timestamp_updates[:in_lab_at] = current_time
      when :resulted
        timestamp_updates[:resulted_at] = current_time
      end

      update!(timestamp_updates)

      # Create event in patient log
      create_status_event(next_status, duration_minutes, timer_status, user_name)

      # Reset timer for next phase
      reset_patient_timer

      true
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  # Get order icon based on type
  def type_icon
    case order_type.to_sym
    when :lab then "🧪"
    when :medication then "💊"
    when :imaging then "📷"
    end
  end

  # Check if order is complete
  def complete?
    resulted?
  end

  # Get status label
  def status_label
    case status.to_sym
    when :ordered then "Ordered"
    when :collected then "Collected"
    when :in_lab then "In Lab"
    when :resulted then "Resulted"
    end
  end

  def status_class
    "status-#{status}"
  end

  def status_value
    self.class.statuses[status]
  end

  private

  def get_previous_timestamp
    case status.to_sym
    when :ordered
      ordered_at
    when :collected
      collected_at
    when :in_lab
      in_lab_at
    else
      nil
    end
  end

  def calculate_timer_status(duration_minutes)
    if duration_minutes <= 20
      "green"
    elsif duration_minutes <= 40
      "yellow"
    else
      "red"
    end
  end

  def create_status_event(new_status, duration_minutes, timer_status, user_name = nil)
    patient = care_pathway.patient

    details = "Order '#{name}' status changed to #{new_status.to_s.humanize}. " \
              "Duration: #{duration_minutes} minutes (#{timer_status})"

    # Ensure the performed_by value is from the allowed list
    performer = if user_name && Event::PERFORMED_BY_OPTIONS.include?(user_name)
                  user_name
                else
                  "System"
                end

    Event.create!(
      patient: patient,
      action: "Order status updated: #{new_status.to_s.humanize}",
      details: details,
      performed_by: performer,
      time: Time.current,
      category: "diagnostic"
    )
  end

  def reset_patient_timer
    # This would trigger any UI updates needed for the patient timer
    # The actual timer is handled in the frontend
  end
end
