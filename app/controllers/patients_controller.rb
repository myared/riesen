class PatientsController < ApplicationController
  before_action :set_patient, only: [:show, :add_event, :update_vitals]
  
  def show
    @vitals = @patient.latest_vital
    @events = @patient.events.recent.limit(20)
    @return_path = request.referrer || root_path
  end
  
  def add_event
    @event = @patient.events.build(event_params)
    @event.time ||= Time.current
    
    if @event.save
      redirect_to patient_path(@patient), notice: 'Event added successfully'
    else
      redirect_to patient_path(@patient), alert: 'Failed to add event'
    end
  end
  
  def update_vitals
    @vital = @patient.vitals.build(vital_params)
    @vital.recorded_at = Time.current
    
    if @vital.save
      Event.record_vitals_update(@patient, 'ED RN')
      redirect_to patient_path(@patient), notice: 'Vitals updated successfully'
    else
      redirect_to patient_path(@patient), alert: 'Failed to update vitals'
    end
  end
  
  private
  
  def set_patient
    @patient = Patient.find(params[:id])
  end
  
  def event_params
    params.require(:event).permit(:action, :details, :performed_by, :category)
  end
  
  def vital_params
    params.require(:vital).permit(:heart_rate, :blood_pressure_systolic, :blood_pressure_diastolic,
                                   :respiratory_rate, :temperature, :spo2, :weight)
  end
end
