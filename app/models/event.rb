class Event < ApplicationRecord
  belongs_to :patient
  
  # Constants for performer roles
  PERFORMED_BY_OPTIONS = [
    'Registration',
    'Triage RN',
    'RP RN',
    'ED RN',
    'Provider',
    'System'
  ].freeze
  
  # Event categories
  CATEGORIES = [
    'triage',
    'clinical',
    'administrative',
    'diagnostic'
  ].freeze
  
  validates :action, presence: true
  validates :performed_by, inclusion: { in: PERFORMED_BY_OPTIONS }
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  
  scope :recent, -> { order(time: :desc) }
  scope :clinical, -> { where(category: 'clinical') }
  scope :triage, -> { where(category: 'triage') }
  scope :by_performer, ->(performer) { where(performed_by: performer) }
  
  # Class methods for common event creation
  def self.record_arrival(patient)
    create!(
      patient: patient,
      action: 'Patient arrived',
      details: "Chief complaint: #{patient.chief_complaint}",
      performed_by: 'Registration',
      time: Time.current,
      category: 'triage'
    )
  end
  
  def self.record_vitals_update(patient, performer = 'ED RN')
    create!(
      patient: patient,
      action: 'Vitals recorded',
      details: 'Vitals updated',
      performed_by: performer,
      time: Time.current,
      category: 'clinical'
    )
  end
end
