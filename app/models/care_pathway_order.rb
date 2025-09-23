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
    resulted: 3,
    administered: 4,
    exam_started: 5,
    exam_completed: 6
  }, prefix: false

  # Common lab orders
  LAB_ORDERS = [
    "Arterial Blood Gas",
    "Basic Metabolic Panel",
    "Blood Culture",
    "BNP",
    "CBC with Differential",
    "Comprehensive Metabolic Panel",
    "COVID-19 PCR",
    "D-Dimer",
    "Human Chorionic Gonadotropin",
    "Influenza A/B",
    "Lactate",
    "Lipid Panel",
    "Liver Function Tests",
    "PT/INR",
    "PTT",
    "Rapid Strep",
    "Troponin",
    "Urinalysis",
    "Urine Culture"
  ].freeze

  # Common medications
  MEDICATIONS = [
    "Acetaminophen 650mg PO",
    "Albuterol Nebulizer",
    "Aspirin 325mg PO",
    "Azithromycin 500mg PO",
    "Ceftriaxone 1g IV",
    "Epinephrine 0.3mg IM",
    "Heparin 5000 units SC",
    "Ibuprofen 400mg PO",
    "Lorazepam 1mg IV",
    "Morphine 2mg IV",
    "Nitroglycerin 0.4mg SL",
    "Normal Saline 1L IV",
    "Prednisone 40mg PO",
    "Reglan",
    "Zofran 4mg IV" 
  ].freeze

  # Common imaging orders
  IMAGING_ORDERS = [
    "CT Abdomen/Pelvis with Contrast",
    "CT Chest with PE Protocol",
    "CT Head without Contrast",
    "Echocardiogram",
    "EKG",
    "MRI Brain",
    "Ultrasound Abdomen",
    "Ultrasound Lower Extremity DVT",
    "X-Ray Abdominal",
    "X-Ray Chest",
    "X-Ray Knee",
    "X-Ray Wrist"
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
  scope :pending, -> {
    where.not(
      "(order_type = ? AND status = ?) OR (order_type IN (?, ?) AND status = ?)",
      order_types[:medication], statuses[:administered],
      order_types[:lab], order_types[:imaging], statuses[:resulted]
    )
  }
  scope :completed, -> {
    where(
      "(order_type = ? AND status = ?) OR (order_type IN (?, ?) AND status = ?)",
      order_types[:medication], statuses[:administered],
      order_types[:lab], order_types[:imaging], statuses[:resulted]
    )
  }

  # Progress to next status
  def advance_status!(user_name = nil)
    return false if complete?

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

      next_status = determine_next_status
      unless next_status
        Rails.logger.warn "Cannot determine next status for Order ID: #{id}, Current Status: #{status}, Order Type: #{order_type}"
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
      when :administered
        timestamp_updates[:administered_at] = current_time
      when :exam_started
        timestamp_updates[:exam_started_at] = current_time
      when :exam_completed
        timestamp_updates[:exam_completed_at] = current_time
      end

      update!(timestamp_updates)

      # Create event in patient log - with error handling
      create_status_event(next_status, duration_minutes, timer_status, user_name)

      # Reset timer for next phase
      reset_patient_timer

      true
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "RecordInvalid in advance_status! for Order ID: #{id}: #{e.record.errors.full_messages.join(', ')}"
    false
  rescue => e
    Rails.logger.error "Unexpected error in advance_status! for Order ID: #{id}: #{e.class}: #{e.message}"
    false
  end

  # Get order icon based on type
  def type_icon
    case order_type.to_sym
    when :lab then "🔬"
    when :medication then "💉"
    when :imaging then "📷"
    end
  end

  # Check if order is complete
  def complete?
    case order_type.to_sym
    when :medication
      administered?
    when :imaging
      resulted?
    when :lab
      resulted?
    else
      resulted?
    end
  end

  # Check if status can be advanced
  def can_advance_status?
    return false if complete?
    determine_next_status.present?
  end

  # Get status label
  def status_label
    case status.to_sym
    when :ordered then "Ordered"
    when :collected then "Collected"
    when :in_lab then "In Lab"
    when :resulted then "Resulted"
    when :administered then "Administered"
    when :exam_started then "Exam Started"
    when :exam_completed then "Exam Completed"
    end
  end

  def status_class
    "status-#{status}"
  end

  def status_value
    self.class.statuses[status]
  end

  # Determine workflow states based on order type
  def workflow_states
    case order_type.to_sym
    when :medication
      [:ordered, :administered]
    when :imaging
      [:ordered, :exam_started, :exam_completed, :resulted]
    when :lab
      [:ordered, :collected, :in_lab, :resulted]
    else
      [:ordered, :collected, :in_lab, :resulted]
    end
  end

  private

  def determine_next_status
    workflow = workflow_states
    current_index = workflow.index(status.to_sym)
    return nil unless current_index && current_index < workflow.length - 1
    workflow[current_index + 1]
  end

  def get_previous_timestamp
    case status.to_sym
    when :ordered
      ordered_at
    when :collected
      collected_at
    when :in_lab
      in_lab_at
    when :resulted
      resulted_at
    when :administered
      administered_at
    when :exam_started
      exam_started_at
    when :exam_completed
      exam_completed_at
    else
      nil
    end
  end

  def calculate_timer_status(duration_minutes)
    settings = ApplicationSetting.current
    target = settings.timer_target_for(order_type, status)
    warning_threshold = settings.warning_threshold_minutes(target)
    critical_threshold = settings.critical_threshold_minutes(target)

    if duration_minutes <= warning_threshold
      "green"
    elsif duration_minutes <= critical_threshold
      "yellow"
    else
      "red"
    end
  end

  def create_status_event(new_status, duration_minutes, timer_status, user_name = nil)
    begin
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
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create status event for Order ID: #{id}: #{e.record.errors.full_messages.join(', ')}"
      # Don't re-raise - this is a non-critical failure
    rescue => e
      Rails.logger.error "Unexpected error creating status event for Order ID: #{id}: #{e.class}: #{e.message}"
      # Don't re-raise - this is a non-critical failure
    end
  end

  def reset_patient_timer
    # This would trigger any UI updates needed for the patient timer
    # The actual timer is handled in the frontend
  end
end
