class CarePathwayClinicalEndpoint < ApplicationRecord
  belongs_to :care_pathway

  # Common clinical endpoints/goals
  CLINICAL_ENDPOINTS = [
    "Pain Control (Score < 4)",
    "Hemodynamic Stability",
    "Normal Vital Signs",
    "Afebrile (Temp < 38°C)",
    "Adequate Oxygenation (SpO2 > 94%)",
    "Symptom Resolution",
    "Bleeding Controlled",
    "Nausea/Vomiting Resolved",
    "Able to Tolerate PO",
    "Ambulating Independently",
    "Mental Status at Baseline",
    "Infection Source Identified",
    "Antibiotics Started",
    "Diagnostic Workup Complete",
    "Disposition Plan Established",
    "Patient Education Completed",
    "Follow-up Arranged",
    "Social Work Evaluation Complete",
    "Safe for Discharge",
    "Family Updated"
  ].freeze

  validates :name, presence: true
  validates :description, presence: true

  scope :pending, -> { where(achieved: false) }
  scope :achieved, -> { where(achieved: true) }
  scope :started, -> { where(started: true) }
  scope :not_started, -> { where(started: false) }

  # Mark endpoint as started
  def start!(user_name = nil)
    update!(
      started: true,
      started_at: Time.current,
      started_by: user_name || "System"
    )
  end

  # Mark endpoint as achieved
  def achieve!(user_name = nil)
    update!(
      achieved: true,
      achieved_at: Time.current,
      achieved_by: user_name || "System"
    )
  end

  # Get status
  def status
    if achieved?
      "Achieved"
    elsif started?
      "Started"
    else
      "Pending"
    end
  end

  # Get status class for styling
  def status_class
    if achieved?
      "endpoint-achieved"
    elsif started?
      "endpoint-started"
    else
      "endpoint-pending"
    end
  end

  # Can advance to next state?
  def can_advance?
    !achieved?
  end

  # Advance to next state
  def advance_status!(user_name = nil)
    if !started?
      start!(user_name)
    elsif !achieved?
      achieve!(user_name)
    else
      false
    end
  end

  # Get next status label
  def next_status_label
    if !started?
      "Started"
    elsif !achieved?
      "Achieved"
    else
      nil
    end
  end

  # Check if can be achieved (must be started first)
  def can_achieve?
    started? && !achieved?
  end

  # Get endpoint icon
  def icon
    "🎯"
  end
end
