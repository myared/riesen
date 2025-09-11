class PatientsController < ApplicationController
  before_action :set_patient, only: [:show, :add_event, :update_vitals, :assign_room]
  
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
  
  def assign_room
    # Determine which type of room to assign based on patient's pathway
    if @patient.rp_eligible?
      available_room = Room.rp_rooms.status_available.first
      room_type = 'RP'
      department_name = 'Results Pending'
    else
      available_room = Room.ed_rooms.status_available.first
      room_type = 'ED'
      department_name = 'Emergency Department'
    end
    
    if available_room
      # Use Room model's assign_patient method
      available_room.assign_patient(@patient)
      
      # Update nursing task if exists
      task = NursingTask.where(patient: @patient, task_type: 'room_assignment', status: 'pending').first
      task&.update(status: 'completed', completed_at: Time.current)
      
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, notice: "✓ Patient assigned to #{room_type} Room #{available_room.number}") }
        format.turbo_stream { redirect_back(fallback_location: root_path, notice: "✓ Patient assigned to #{room_type} Room #{available_room.number}") }
        format.json { render json: { success: true, room: available_room.number } }
      end
    else
      respond_to do |format|
        format.html { 
          redirect_back(fallback_location: root_path, 
                       alert: "⚠️ Cannot assign room: The #{department_name} is full. Please wait for a room to become available.")
        }
        format.json { render json: { success: false, error: "No #{room_type} rooms available" }, status: :unprocessable_entity }
      end
    end
  end
  
  def generate
    generator = PatientGenerator.new
    patient = generator.generate
    
    if patient.save
      # Generate initial vitals for the patient
      patient.vitals.create(
        heart_rate: rand(60..120),
        blood_pressure_systolic: rand(90..160),
        blood_pressure_diastolic: rand(60..100),
        respiratory_rate: rand(12..24),
        temperature: rand(97.0..101.0).round(1),
        spo2: rand(92..100),
        weight: rand(50.0..120.0).round(1),
        recorded_at: Time.current
      )
      
      # Record initial event
      patient.events.create(
        time: Time.current,
        action: 'Arrival',
        details: "Patient arrived with #{patient.chief_complaint}",
        performed_by: 'System',
        category: 'Registration'
      )
      
      redirect_back(fallback_location: root_path, notice: "Patient #{patient.full_name} added successfully")
    else
      redirect_back(fallback_location: root_path, alert: 'Failed to generate patient')
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
