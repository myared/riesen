class Vital < ApplicationRecord
  belongs_to :patient
  
  validates :heart_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :blood_pressure_systolic, numericality: { greater_than: 0 }, allow_nil: true
  validates :blood_pressure_diastolic, numericality: { greater_than: 0 }, allow_nil: true
  validates :respiratory_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :spo2, numericality: { in: 0..100 }, allow_nil: true
  
  def blood_pressure
    return nil unless blood_pressure_systolic && blood_pressure_diastolic
    "#{blood_pressure_systolic}/#{blood_pressure_diastolic}"
  end
  
  def temperature_fahrenheit
    return nil unless temperature
    (temperature * 9/5 + 32).round(1)
  end
end
