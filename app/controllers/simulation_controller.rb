class SimulationController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def add_patient
    patient = PatientGenerator.new.generate
    
    if patient.save
      PatientArrivalService.new(patient).process
      redirect_back(fallback_location: root_path, 
                    notice: "Patient #{patient.full_name} added successfully")
    else
      redirect_back(fallback_location: root_path, 
                    alert: "Failed to add patient: #{patient.errors.full_messages.join(', ')}")
    end
  end
  
  def advance_time
    minutes = params[:minutes].to_i.nonzero? || 10
    TimeAdvancer.new(minutes).advance_all_patients
    
    redirect_back(fallback_location: root_path,
                  notice: "Time advanced by #{minutes} minutes")
  end
end