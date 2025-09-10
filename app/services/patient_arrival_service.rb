class PatientArrivalService
  attr_reader :patient
  
  def initialize(patient)
    @patient = patient
  end
  
  def process
    create_arrival_event
    create_initial_vitals if patient.vitals.empty?
    patient
  end
  
  private
  
  def create_arrival_event
    Event.record_arrival(patient)
  end
  
  def create_initial_vitals
    patient.vitals.create!(
      heart_rate: generate_heart_rate,
      blood_pressure_systolic: generate_systolic_bp,
      blood_pressure_diastolic: generate_diastolic_bp,
      respiratory_rate: generate_respiratory_rate,
      temperature: generate_temperature,
      spo2: generate_spo2,
      weight: generate_weight,
      recorded_at: Time.current
    )
  end
  
  def generate_heart_rate
    # Heart rate based on ESI level - more critical patients may have abnormal rates
    case patient.esi_level
    when 1 then rand([30..50, 120..160].sample)  # Bradycardia or tachycardia
    when 2 then rand([50..60, 100..130].sample)  # Mild abnormality
    else rand(60..100)                            # Normal range
    end
  end
  
  def generate_systolic_bp
    # Blood pressure based on ESI level
    case patient.esi_level
    when 1 then rand([70..90, 160..200].sample)   # Hypotension or hypertension
    when 2 then rand([90..110, 140..160].sample)  # Mild abnormality
    else rand(110..140)                            # Normal range
    end
  end
  
  def generate_diastolic_bp
    # Diastolic typically 30-50 points lower than systolic
    case patient.esi_level
    when 1 then rand([40..60, 100..120].sample)
    when 2 then rand([60..70, 90..100].sample)
    else rand(70..90)
    end
  end
  
  def generate_respiratory_rate
    case patient.esi_level
    when 1 then rand([8..10, 24..30].sample)  # Bradypnea or tachypnea
    when 2 then rand([10..12, 20..24].sample) # Mild abnormality
    else rand(12..20)                          # Normal range
    end
  end
  
  def generate_temperature
    # Temperature in Celsius
    case patient.esi_level
    when 1, 2 then rand([35.0..36.0, 38.5..40.0].sample).round(1)  # Hypothermia or fever
    else rand(36.0..37.5).round(1)                                  # Normal range
    end
  end
  
  def generate_spo2
    case patient.esi_level
    when 1 then rand(85..92)   # Hypoxia
    when 2 then rand(92..95)   # Mild hypoxia
    else rand(95..100)         # Normal range
    end
  end
  
  def generate_weight
    # Weight based on age
    case patient.age
    when 0..12 then rand(15..40)    # Children
    when 13..17 then rand(40..80)   # Adolescents
    else rand(50..120)              # Adults
    end
  end
end