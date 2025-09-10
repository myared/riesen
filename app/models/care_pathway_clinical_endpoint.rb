class CarePathwayClinicalEndpoint < ApplicationRecord
  belongs_to :care_pathway
  
  # Common clinical endpoints/goals
  CLINICAL_ENDPOINTS = [
    'Pain Control (Score < 4)',
    'Hemodynamic Stability',
    'Normal Vital Signs',
    'Afebrile (Temp < 38°C)',
    'Adequate Oxygenation (SpO2 > 94%)',
    'Symptom Resolution',
    'Bleeding Controlled',
    'Nausea/Vomiting Resolved',
    'Able to Tolerate PO',
    'Ambulating Independently',
    'Mental Status at Baseline',
    'Infection Source Identified',
    'Antibiotics Started',
    'Diagnostic Workup Complete',
    'Disposition Plan Established',
    'Patient Education Completed',
    'Follow-up Arranged',
    'Social Work Evaluation Complete',
    'Safe for Discharge',
    'Family Updated'
  ].freeze
  
  validates :name, presence: true
  validates :description, presence: true
  
  scope :pending, -> { where(achieved: false) }
  scope :achieved, -> { where(achieved: true) }
  
  # Mark endpoint as achieved
  def achieve!(user = nil)
    update!(
      achieved: true,
      achieved_at: Time.current,
      achieved_by: user&.name || 'System'
    )
  end
  
  # Get status
  def status
    achieved? ? 'Achieved' : 'Pending'
  end
  
  # Get status class for styling
  def status_class
    achieved? ? 'endpoint-achieved' : 'endpoint-pending'
  end
  
  # Get endpoint icon
  def icon
    '🎯'
  end
end