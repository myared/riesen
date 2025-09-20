class CarePathwaysController < ApplicationController
  before_action :set_patient
  before_action :set_care_pathway, only: [ :show, :update ]

  def index
    # Store the referrer in the session for back navigation
    session[:care_pathway_referrer] = params[:referrer] if params[:referrer].present?

    # Determine the expected pathway type based on patient location
    expected_pathway_type = determine_pathway_type(@patient)

    # Find the most recent care pathway of the expected type
    @care_pathway = @patient.care_pathways
                            .where(pathway_type: expected_pathway_type)
                            .order(created_at: :desc)
                            .first

    # If no pathway of the expected type exists, create one
    if @care_pathway.nil?
      @care_pathway = @patient.care_pathways.build(pathway_type: expected_pathway_type)
      @care_pathway.started_at = Time.current
      @care_pathway.started_by = current_user_name

      if @care_pathway.save
        if @care_pathway.pathway_type_triage?
          create_triage_steps
        elsif @care_pathway.pathway_type_emergency_room?
          create_emergency_room_components
        end

        respond_to do |format|
          format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, referrer: params[:referrer]) }
          format.json { render json: @care_pathway, status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_to root_path, alert: "Failed to create care pathway" }
          format.json { render json: { error: "Failed to create care pathway" }, status: :unprocessable_entity }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, referrer: params[:referrer]) }
        format.json { render json: { id: @care_pathway.id, pathway_type: @care_pathway.pathway_type } }
      end
    end
  end

  def show
    # Store the referrer in the session if provided
    session[:care_pathway_referrer] = params[:referrer] if params[:referrer].present?

    @steps = @care_pathway.care_pathway_steps.ordered if @care_pathway.pathway_type_triage?
    @orders = @care_pathway.care_pathway_orders.order(:name) if @care_pathway.pathway_type_emergency_room?
    @procedures = @care_pathway.care_pathway_procedures if @care_pathway.pathway_type_emergency_room?
    @clinical_endpoints = @care_pathway.care_pathway_clinical_endpoints if @care_pathway.pathway_type_emergency_room?

    respond_to do |format|
      format.html { render layout: "care_pathway" }
      format.json { render json: care_pathway_json }
    end
  end

  def create
    @care_pathway = @patient.care_pathways.build(care_pathway_params)
    @care_pathway.started_at = Time.current
    @care_pathway.started_by = current_user_name

    if @care_pathway.save
      # Initialize steps for triage pathway
      if @care_pathway.pathway_type_triage?
        create_triage_steps
      end

      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: @care_pathway, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json { render json: @care_pathway.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @care_pathway.update(care_pathway_params)
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: @care_pathway }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json { render json: @care_pathway.errors, status: :unprocessable_entity }
      end
    end
  end

  # Complete a triage step
  def complete_step
    @care_pathway = @patient.care_pathways.find(params[:id])
    @step = @care_pathway.care_pathway_steps.find(params[:step_id])

    # Handle bed assignment destination override
    if @step.name == "Bed Assignment" && params[:destination].present?
      # Update patient's RP eligibility based on user's selection
      @patient.update(rp_eligible: params[:destination] == "rp")

      Rails.logger.info "Bed Assignment Override: Patient #{@patient.id} (#{@patient.full_name}) assigned to #{params[:destination].upcase} (RP eligible: #{@patient.rp_eligible?})"
    end

    # Special handling for Pending Transfer with RP patients
    if @step.name == "Pending Transfer" && @patient.rp_eligible?
      available_room = Room.rp_rooms.status_available.first
      if !available_room
        # No RP rooms available, don't complete the step
        Rails.logger.warn "Cannot complete Pending Transfer - no RP rooms available for patient #{@patient.id} (#{@patient.full_name})"
        flash[:alert] = "⚠️ No RP rooms available. Patient remains in Pending Transfer status."

        respond_to do |format|
          format.html { redirect_back(fallback_location: patient_care_pathway_path(@patient, @care_pathway)) }
          format.json { render json: { success: false, error: "No RP rooms available" }, status: :unprocessable_entity }
        end
        return
      end
    end

    if @step.complete!(current_user_name)
      # Record event for step completion
      Event.create!(
        patient: @patient,
        action: "#{@step.name} completed",
        details: @step.name == "Bed Assignment" ? "Patient assigned to #{params[:destination]&.upcase || (@patient.rp_eligible? ? 'RP' : 'ED')}" : "Care pathway step completed",
        performed_by: "Triage RN",
        time: Time.current,
        category: "triage"
      )

      # Handle step-specific transitions
      case @step.name
      when "Bed Assignment"
        # When bed assignment is completed, move to pending transfer status
        updates = { location_status: :pending_transfer }
        updates[:triage_completed_at] = Time.current if @patient.triage_completed_at.blank?
        @patient.update(updates)

        # Start RP eligibility timer if patient is RP eligible
        if @patient.rp_eligible? && @patient.rp_eligibility_started_at.blank?
          @patient.update(rp_eligibility_started_at: Time.current)
        end

      when "Pending Transfer"
        # When pending transfer is completed for RP patients, directly assign them to an RP room
        if @patient.rp_eligible?
          available_room = Room.rp_rooms.status_available.first
          if available_room
            # Use Room model's assign_patient method to handle the assignment
            available_room.assign_patient(@patient)

            Rails.logger.info "Pending Transfer completed: Patient #{@patient.id} (#{@patient.full_name}) assigned to RP Room #{available_room.number}"
          end
        else
          # For ED patients, move to needs room assignment as before
          @patient.update(
            location_status: :needs_room_assignment,
            room_assignment_needed_at: Time.current
          )

          # Create nursing task for room assignment
          NursingTask.create_room_assignment_task(@patient)
        end
      end

      # Check if pathway is complete
      if @care_pathway.complete?
        @care_pathway.update(status: :completed, completed_at: Time.current, completed_by: current_user_name)

        # Record pathway completion event
        Event.create!(
          patient: @patient,
          action: "Triage pathway completed",
          details: "Patient ready for #{@patient.rp_eligible? ? 'RP' : 'ED'} placement",
          performed_by: "Triage RN",
          time: Time.current,
          category: "triage"
        )
      else
        @care_pathway.update(status: :in_progress) if @care_pathway.status_not_started?
      end

      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway),
                      status: :see_other # Important for Turbo to handle the redirect properly
        }
        format.json { render json: { success: true, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway),
                      alert: "Failed to complete step",
                      status: :see_other
        }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
    end
  end

  # Add an order
  def add_order
    @care_pathway = @patient.care_pathways.find(params[:id])
    @order = @care_pathway.care_pathway_orders.build(order_params)
    @order.ordered_at = Time.current
    @order.ordered_by = current_user_name

    if @order.save
      # Log the order creation to patient event log
      Event.create!(
        patient: @patient,
        action: "Order placed: #{@order.name}",
        details: "#{@order.order_type.capitalize} order '#{@order.name}' was placed",
        performed_by: current_user_name,
        time: Time.current,
        category: "diagnostic"
      )

      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway),
                      status: :see_other,
                      notice: "Order added successfully"
        }
        format.json { render json: @order, status: :created }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway),
                      alert: "Failed to add order",
                      status: :unprocessable_entity
        }
        format.json { render json: @order.errors, status: :unprocessable_entity }
      end
    end
  end

  # Update order status
  def update_order_status
    begin
      Rails.logger.info "update_order_status called - Patient: #{params[:patient_id]}, Care Pathway: #{params[:id]}, Order: #{params[:order_id]}"

      @care_pathway = @patient.care_pathways.find(params[:id])

      # Verify care pathway belongs to the patient
      unless @care_pathway.patient_id == @patient.id
        raise ActiveRecord::RecordNotFound, "Care pathway does not belong to patient"
      end

      @order = @care_pathway.care_pathway_orders.find(params[:order_id])

      Rails.logger.info "Found order: #{@order.name} (#{@order.order_type}) with status: #{@order.status}"

      unless @order.can_advance_status?
        Rails.logger.warn "Order cannot be advanced - ID: #{@order.id}, Status: #{@order.status}, Complete: #{@order.complete?}"
        respond_to do |format|
          format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "orders"), alert: "Order is already complete or cannot be advanced", status: :unprocessable_entity }
          format.json { render json: { success: false, error: "Order cannot be advanced from current status" }, status: :unprocessable_entity }
        end
        return
      end

      if @order.advance_status!(current_user_name)
        Rails.logger.info "Successfully advanced order #{@order.id} to status: #{@order.status}"
        respond_to do |format|
          format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "orders"), status: :see_other }
          format.json { render json: { success: true, status: @order.status, progress: @care_pathway.progress_percentage } }
        end
      else
        Rails.logger.error "Failed to advance order status for Order ID: #{params[:order_id]}, Current Status: #{@order.status}"
        respond_to do |format|
          format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "orders"), alert: "Failed to update order status", status: :unprocessable_entity }
          format.json { render json: { success: false, error: "Cannot advance order status from current state" }, status: :unprocessable_entity }
        end
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "Record not found in update_order_status: #{e.message}"
      Rails.logger.error "Patient ID: #{params[:patient_id]}, Care Pathway ID: #{params[:id]}, Order ID: #{params[:order_id]}"
      respond_to do |format|
        format.html { redirect_to patient_path(@patient), alert: "Order or care pathway not found", status: :not_found }
        format.json { render json: { success: false, error: "Record not found" }, status: :not_found }
      end
    rescue => e
      Rails.logger.error "Unexpected error in update_order_status: #{e.class}: #{e.message}"
      Rails.logger.error "Patient ID: #{params[:patient_id]}, Care Pathway ID: #{params[:id]}, Order ID: #{params[:order_id]}"
      Rails.logger.error e.backtrace.join("\n")
      respond_to do |format|
        format.html { redirect_to patient_path(@patient), alert: "An error occurred while updating the order status", status: :internal_server_error }
        format.json { render json: { success: false, error: "Internal server error" }, status: :internal_server_error }
      end
    end
  end

  # Add a procedure
  def add_procedure
    @care_pathway = @patient.care_pathways.find(params[:id])
    @procedure = @care_pathway.care_pathway_procedures.build(procedure_params)

    if @procedure.save
      # Log the procedure creation to patient event log
      Event.create!(
        patient: @patient,
        action: "Procedure ordered: #{@procedure.name}",
        details: "Procedure '#{@procedure.name}' was ordered#{@procedure.description.present? ? ": #{@procedure.description}" : ""}",
        performed_by: current_user_name,
        time: Time.current,
        category: "clinical"
      )

      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: params[:active_tab]),
                      status: :see_other,
                      notice: "Procedure added successfully"
        }
        format.json { render json: @procedure, status: :created }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: params[:active_tab]),
                      alert: "Failed to add procedure",
                      status: :unprocessable_entity
        }
        format.json { render json: @procedure.errors, status: :unprocessable_entity }
      end
    end
  end

  # Complete a procedure
  def complete_procedure
    @care_pathway = @patient.care_pathways.find(params[:id])
    @procedure = @care_pathway.care_pathway_procedures.find(params[:procedure_id])

    if @procedure.complete!(current_user_name)
      # Log the procedure completion to patient event log
      Event.create!(
        patient: @patient,
        action: "Procedure completed: #{@procedure.name}",
        details: "Procedure '#{@procedure.name}' was completed",
        performed_by: current_user_name,
        time: Time.current,
        category: "clinical"
      )

      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "procedures") }
        format.json { render json: { success: true, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "procedures"), alert: "Failed to complete procedure" }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
    end
  end

  # Add a clinical endpoint
  def add_clinical_endpoint
    @care_pathway = @patient.care_pathways.find(params[:id])
    endpoint_data = endpoint_params

    # Set a default description based on the goal name if not provided
    if endpoint_data[:description].blank?
      endpoint_data[:description] = generate_endpoint_description(endpoint_data[:name])
    end

    @endpoint = @care_pathway.care_pathway_clinical_endpoints.build(endpoint_data)

    if @endpoint.save
      # Log the clinical goal creation to patient event log
      Event.create!(
        patient: @patient,
        action: "Clinical goal set: #{@endpoint.name}",
        details: "Clinical goal '#{@endpoint.name}' was established#{@endpoint.description.present? ? ": #{@endpoint.description}" : ""}",
        performed_by: current_user_name,
        time: Time.current,
        category: "clinical"
      )

      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: params[:active_tab]),
                      status: :see_other,
                      notice: "Clinical goal added successfully"
        }
        format.json { render json: @endpoint, status: :created }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: params[:active_tab]),
                      alert: "Failed to add clinical endpoint",
                      status: :unprocessable_entity
        }
        format.json { render json: @endpoint.errors, status: :unprocessable_entity }
      end
    end
  end

  # Achieve a clinical endpoint
  def achieve_endpoint
    @care_pathway = @patient.care_pathways.find(params[:id])
    @endpoint = @care_pathway.care_pathway_clinical_endpoints.find(params[:endpoint_id])

    if @endpoint.achieve!(current_user_name)
      # Log the clinical goal achievement to patient event log
      Event.create!(
        patient: @patient,
        action: "Clinical goal achieved: #{@endpoint.name}",
        details: "Clinical goal '#{@endpoint.name}' was achieved",
        performed_by: current_user_name,
        time: Time.current,
        category: "clinical"
      )

      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "endpoints") }
        format.json { render json: { success: true, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway, active_tab: "endpoints"), alert: "Failed to achieve endpoint" }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
    end
  end

  # Discharge a patient
  def discharge
    @patient.discharge!(performed_by: current_user_name)

    respond_to do |format|
      format.html { redirect_to dashboard_path_for_role, notice: "Patient successfully discharged" }
      format.json { render json: { success: true, message: "Patient discharged successfully" } }
    end
  rescue Patient::NotDischargeable => e
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, alert: e.message) }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  private

  def set_patient
    @patient = Patient.find(params[:patient_id])
  end

  def set_care_pathway
    @care_pathway = @patient.care_pathways.find(params[:id])
  end

  def care_pathway_params
    params.require(:care_pathway).permit(:pathway_type, :status)
  end

  def order_params
    # Sanitize and validate parameters
    permitted = params.require(:order).permit(:name, :order_type, :notes)

    # Validate order_type is one of the allowed values
    unless %w[lab medication imaging].include?(permitted[:order_type])
      raise ActionController::ParameterMissing.new(:order_type)
    end

    # Ensure name is from the predefined lists
    valid_names = case permitted[:order_type]
    when "lab" then CarePathwayOrder::LAB_ORDERS
    when "medication" then CarePathwayOrder::MEDICATIONS
    when "imaging" then CarePathwayOrder::IMAGING_ORDERS
    else []
    end

    unless valid_names.include?(permitted[:name])
      raise ActionController::ParameterMissing.new(:name)
    end

    permitted
  end

  def procedure_params
    permitted = params.require(:procedure).permit(:name, :description, :notes)

    # Validate procedure name is from predefined list
    unless CarePathwayProcedure::PROCEDURES.include?(permitted[:name])
      raise ActionController::ParameterMissing.new(:name)
    end

    permitted
  end

  def endpoint_params
    permitted = params.require(:endpoint).permit(:name, :description, :notes)

    # Validate endpoint name is from predefined list
    unless CarePathwayClinicalEndpoint::CLINICAL_ENDPOINTS.include?(permitted[:name])
      raise ActionController::ParameterMissing.new(:name)
    end

    permitted
  end

  def generate_endpoint_description(name)
    # Generate default descriptions for clinical endpoints
    descriptions = {
      "Pain Control (Score < 4)" => "Patient reports pain score less than 4/10",
      "Hemodynamic Stability" => "Vital signs stable for at least 30 minutes",
      "Normal Vital Signs" => "All vital signs within normal limits",
      "Afebrile (Temp < 38°C)" => "Temperature below 38°C",
      "Adequate Oxygenation (SpO2 > 94%)" => "Oxygen saturation consistently above 94%",
      "Symptom Resolution" => "Primary symptoms have resolved",
      "Safe for Discharge" => "Patient meets all discharge criteria",
      "Follow-up Arranged" => "Appropriate follow-up care scheduled",
      "Infection Source Identified" => "Source of infection has been identified",
      "Antibiotic Started" => "Appropriate antibiotic therapy initiated",
      "Fluid Resuscitation Complete" => "Adequate fluid resuscitation achieved",
      "Diagnostic Workup Complete" => "All necessary diagnostic tests completed",
      "Specialist Consulted" => "Appropriate specialist consultation completed",
      "Family Updated" => "Family has been informed of patient status"
    }
    descriptions[name] || "Goal: #{name}"
  end

  def current_user_name
    # Placeholder - replace with actual current user logic
    # For now, return a valid performer role
    "ED RN"
  end

  def dashboard_path_for_role
    # Determine which dashboard to redirect to based on referrer
    case session[:care_pathway_referrer]
    when "triage"
      dashboard_triage_path
    when "rp"
      dashboard_rp_path
    when "ed_rn"
      dashboard_ed_rn_path
    when "provider"
      dashboard_provider_path
    when "charge_rn"
      dashboard_charge_rn_path
    else
      dashboard_ed_rn_path
    end
  end

  def create_triage_steps
    steps = [
      { name: "Check-In", sequence: 0 },
      { name: "Intake", sequence: 1 },
      { name: "Bed Assignment", sequence: 2 },
      { name: "Pending Transfer", sequence: 3 }
    ]

    steps.each do |step_data|
      @care_pathway.care_pathway_steps.create!(step_data)
    end
  end

  def determine_pathway_type(patient)
    # Patients in triage or waiting room get triage pathway
    # Patients in RP, ED Room, Treatment, or needing room assignment get emergency room pathway
    case patient.location_status
    when "waiting_room", "triage"
      "triage"
    when "needs_room_assignment", "results_pending", "ed_room", "treatment"
      "emergency_room"
    else
      "triage" # Default to triage if status is unknown
    end
  end

  def create_emergency_room_components
    # No default orders - providers will add orders as needed

    # No default procedures - will be added based on clinical needs

    # No default clinical endpoints - will be added based on patient condition
  end

  def care_pathway_json
    {
      id: @care_pathway.id,
      pathway_type: @care_pathway.pathway_type,
      status: @care_pathway.status,
      progress_percentage: @care_pathway.progress_percentage,
      steps: @steps&.map { |s| step_json(s) },
      orders: @orders&.map { |o| order_json(o) },
      procedures: @procedures&.map { |p| procedure_json(p) },
      clinical_endpoints: @clinical_endpoints&.map { |e| endpoint_json(e) }
    }
  end

  def step_json(step)
    {
      id: step.id,
      name: step.name,
      sequence: step.sequence,
      completed: step.completed,
      completed_at: step.completed_at,
      status: step.status
    }
  end

  def order_json(order)
    {
      id: order.id,
      name: order.name,
      order_type: order.order_type,
      status: order.status,
      status_label: order.status_label
    }
  end

  def procedure_json(procedure)
    {
      id: procedure.id,
      name: procedure.name,
      completed: procedure.completed,
      status: procedure.status
    }
  end

  def endpoint_json(endpoint)
    {
      id: endpoint.id,
      name: endpoint.name,
      description: endpoint.description,
      achieved: endpoint.achieved,
      status: endpoint.status
    }
  end
end
