class TimeAdvancer
  attr_reader :minutes
  
  def initialize(minutes)
    @minutes = minutes.to_i
  end
  
  def advance_all_patients
    Patient.find_each do |patient|
      advance_patient_time(patient)
    end
  end
  
  private
  
  def advance_patient_time(patient)
    new_wait_time = (patient.wait_time_minutes || 0) + minutes
    patient.update(wait_time_minutes: new_wait_time)
    
    # Log time advancement for critical patients who are overdue
    if patient.critical? && patient.overdue?
      log_overdue_alert(patient)
    end
  end
  
  def log_overdue_alert(patient)
    Event.create!(
      patient: patient,
      action: 'Wait time alert',
      details: "Patient has been waiting #{patient.wait_time_minutes} minutes (Target: #{patient.esi_target_minutes}m)",
      performed_by: 'System',
      time: Time.current,
      category: 'administrative'
    )
  end
end