class PatientsController < ApplicationController
  before_action :set_patient, only: [:show, :add_event, :update_vitals, :assign_room, :add_demo_orders]
  
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
    # Handle pending transfer patients who are being assigned early (at 75% completion)
    if @patient.location_pending_transfer?
      handle_early_room_assignment
    else
      handle_standard_room_assignment
    end
  end

  private

  def handle_early_room_assignment
    # Complete the pending transfer step if it exists
    pathway = @patient.care_pathways.pathway_type_triage.where(status: [:not_started, :in_progress]).first
    if pathway
      pending_transfer_step = pathway.care_pathway_steps.find_by(name: 'Pending Transfer')
      if pending_transfer_step && !pending_transfer_step.completed?
        pending_transfer_step.complete!('System - Early Room Assignment')

        # Mark the pathway as complete
        pathway.update(status: :completed, completed_at: Time.current, completed_by: 'System')

        # Record event
        Event.create!(
          patient: @patient,
          action: "Early room assignment from Pending Transfer",
          details: "Patient assigned room before completing full triage pathway (at 75%)",
          performed_by: current_user_name,
          time: Time.current,
          category: "administrative"
        )
      end
    end

    # Update patient status to needs room assignment
    @patient.update(
      location_status: :needs_room_assignment,
      room_assignment_needed_at: Time.current
    )

    # Create nursing task if it doesn't exist
    NursingTask.create_room_assignment_task(@patient) unless NursingTask.where(patient: @patient, task_type: 'room_assignment', status: 'pending').exists?

    # Now proceed with standard room assignment
    handle_standard_room_assignment
  end

  def handle_standard_room_assignment
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
        format.json { render json: { success: false, error: "No #{room_type} rooms available" }, status: :unprocessable_content }
      end
    end
  end

  def current_user_name
    # Map session roles to valid Event performer options
    role = session[:current_role]

    case role
    when 'triage'
      'Triage RN'
    when 'rp'
      'RP RN'
    when 'ed_rn'
      'ED RN'
    when 'provider'
      'Provider'
    when 'charge_rn'
      'ED RN'  # Charge RN acts as ED RN for events
    else
      'System'
    end
  end

  public

  def add_demo_orders
    # Find or create care pathway for this patient
    care_pathway = @patient.care_pathways.find_or_create_by(
      pathway_type: 'emergency_room',
      status: 'in_progress'
    )

    # Demo medications to add
    medications = [
      "Morphine 2mg IV",
      "Reglan",
      "Zofran 4mg IV"
    ]

    # Demo imaging orders to add
    imaging_orders = [
      "X-Ray Knee",
      "CT Abdomen/Pelvis with Contrast"
    ]

    # Demo lab orders to add
    lab_orders = [
      "CBC with Differential",
      "Comprehensive Metabolic Panel",
      "Urinalysis",
      "Troponin",
      "Urine Culture"
    ]

    # Add all medications
    medications.each do |med_name|
      care_pathway.care_pathway_orders.find_or_create_by(
        name: med_name,
        order_type: 'medication'
      ) do |order|
        order.status = 'ordered'
        order.ordered_at = Time.current
        order.ordered_by = "ED RN"
      end
    end

    # Add all imaging orders
    imaging_orders.each do |imaging_name|
      care_pathway.care_pathway_orders.find_or_create_by(
        name: imaging_name,
        order_type: 'imaging'
      ) do |order|
        order.status = 'ordered'
        order.ordered_at = Time.current
        order.ordered_by = "ED RN"
      end
    end

    # Add all lab orders
    lab_orders.each do |lab_name|
      care_pathway.care_pathway_orders.find_or_create_by(
        name: lab_name,
        order_type: 'lab'
      ) do |order|
        order.status = 'ordered'
        order.ordered_at = Time.current
        order.ordered_by = "ED RN"
      end
    end

    # Record event in patient log
    @patient.events.create(
      time: Time.current,
      action: 'Demo orders added',
      details: "Added #{medications.count} medications, #{imaging_orders.count} imaging orders, and #{lab_orders.count} lab orders for demo purposes",
      performed_by: 'System',
      category: 'diagnostic'
    )

    redirect_to patient_path(@patient), notice: '✓ All demo orders have been added successfully!'
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
