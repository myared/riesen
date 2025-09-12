class SimulationController < ApplicationController
  def add_patient
    patient = PatientGenerator.new.generate.tap(&:save!)
    PatientArrivalService.new(patient).process
    
    redirect_back fallback_location: root_path, 
                  notice: "Patient #{patient.full_name} added successfully"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: root_path, 
                  alert: e.record.errors.full_messages.to_sentence
  end
end