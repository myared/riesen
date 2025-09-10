class CarePathwaysController < ApplicationController
  before_action :set_patient
  before_action :set_care_pathway, only: [:show, :update]
  
  def index
    # Find the most recent care pathway (including completed ones)
    @care_pathway = @patient.care_pathways.order(created_at: :desc).first
    
    if @care_pathway
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: { id: @care_pathway.id, pathway_type: @care_pathway.pathway_type } }
      end
    else
      # Create a new triage pathway if none exists
      @care_pathway = @patient.care_pathways.build(pathway_type: 'triage')
      @care_pathway.started_at = Time.current
      @care_pathway.started_by = current_user_name
      
      if @care_pathway.save
        create_triage_steps
        respond_to do |format|
          format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
          format.json { render json: @care_pathway, status: :created }
        end
      else
        respond_to do |format|
          format.html { redirect_to root_path, alert: 'Failed to create care pathway' }
          format.json { render json: { error: 'Failed to create care pathway' }, status: :unprocessable_entity }
        end
      end
    end
  end
  
  def show
    @steps = @care_pathway.care_pathway_steps.ordered if @care_pathway.pathway_type_triage?
    @orders = @care_pathway.care_pathway_orders if @care_pathway.pathway_type_emergency_room?
    @procedures = @care_pathway.care_pathway_procedures if @care_pathway.pathway_type_emergency_room?
    @clinical_endpoints = @care_pathway.care_pathway_clinical_endpoints if @care_pathway.pathway_type_emergency_room?
    
    respond_to do |format|
      format.html { render layout: false }
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
    
    if @step.complete!(current_user_name)
      # Record event for step completion
      Event.create!(
        patient: @patient,
        action: "#{@step.name} completed",
        details: "Care pathway step completed",
        performed_by: 'Triage RN',
        time: Time.current,
        category: 'triage'
      )
      
      # Check if pathway is complete
      if @care_pathway.complete?
        @care_pathway.update(status: :completed, completed_at: Time.current, completed_by: current_user_name)
        
        # Record pathway completion event
        Event.create!(
          patient: @patient,
          action: "Triage pathway completed",
          details: "Patient ready for #{@patient.rp_eligible? ? 'RP' : 'ED'} placement",
          performed_by: 'Triage RN',
          time: Time.current,
          category: 'triage'
        )
        
        # Update patient location status and create nursing task
        @patient.update(location_status: :needs_room_assignment, triage_completed_at: Time.current)
        
        # Create nursing task for room assignment
        NursingTask.create_room_assignment_task(@patient)
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
                      alert: 'Failed to complete step',
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
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: @order, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to add order' }
        format.json { render json: @order.errors, status: :unprocessable_entity }
      end
    end
  end
  
  # Update order status
  def update_order_status
    @care_pathway = @patient.care_pathways.find(params[:id])
    @order = @care_pathway.care_pathway_orders.find(params[:order_id])
    
    if @order.advance_status!
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: { success: true, status: @order.status, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to update order status' }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
    end
  end
  
  # Add a procedure
  def add_procedure
    @care_pathway = @patient.care_pathways.find(params[:id])
    @procedure = @care_pathway.care_pathway_procedures.build(procedure_params)
    
    if @procedure.save
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: @procedure, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to add procedure' }
        format.json { render json: @procedure.errors, status: :unprocessable_entity }
      end
    end
  end
  
  # Complete a procedure
  def complete_procedure
    @care_pathway = @patient.care_pathways.find(params[:id])
    @procedure = @care_pathway.care_pathway_procedures.find(params[:procedure_id])
    
    if @procedure.complete!(current_user_name)
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: { success: true, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to complete procedure' }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
    end
  end
  
  # Add a clinical endpoint
  def add_clinical_endpoint
    @care_pathway = @patient.care_pathways.find(params[:id])
    @endpoint = @care_pathway.care_pathway_clinical_endpoints.build(endpoint_params)
    
    if @endpoint.save
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: @endpoint, status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to add clinical endpoint' }
        format.json { render json: @endpoint.errors, status: :unprocessable_entity }
      end
    end
  end
  
  # Achieve a clinical endpoint
  def achieve_endpoint
    @care_pathway = @patient.care_pathways.find(params[:id])
    @endpoint = @care_pathway.care_pathway_clinical_endpoints.find(params[:endpoint_id])
    
    if @endpoint.achieve!(current_user_name)
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway) }
        format.json { render json: { success: true, progress: @care_pathway.progress_percentage } }
      end
    else
      respond_to do |format|
        format.html { redirect_to patient_care_pathway_path(@patient, @care_pathway), alert: 'Failed to achieve endpoint' }
        format.json { render json: { success: false }, status: :unprocessable_entity }
      end
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
    params.require(:order).permit(:name, :order_type, :notes)
  end
  
  def procedure_params
    params.require(:procedure).permit(:name, :description, :notes)
  end
  
  def endpoint_params
    params.require(:endpoint).permit(:name, :description, :notes)
  end
  
  def current_user_name
    # Placeholder - replace with actual current user logic
    'Current User'
  end
  
  def create_triage_steps
    steps = [
      { name: 'Check-In', sequence: 0 },
      { name: 'Intake', sequence: 1 },
      { name: 'Bed Assignment', sequence: 2 }
    ]
    
    steps.each do |step_data|
      @care_pathway.care_pathway_steps.create!(step_data)
    end
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