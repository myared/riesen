class DashboardController < ApplicationController
  before_action :load_dashboard_stats
  
  def triage
    @patients = Patient.includes(:vitals, :events).in_triage.by_arrival_time
    wait_times = @patients.map(&:wait_time_minutes).compact
    @avg_wait_time = wait_times.any? ? (wait_times.sum / wait_times.size.to_f).round : 0
  end

  def rp
    # Include both patients in RP and those waiting for RP room assignment
    @patients = Patient.includes(:vitals, :events)
                       .in_results_pending
                       .or(Patient.needs_rp_assignment)
                       .by_priority_time
  end

  def ed_rn
    # Include both patients in ED and those waiting for ED room assignment
    @patients = Patient.includes(:vitals, :events)
                       .in_ed_treatment
                       .or(Patient.needs_ed_assignment)
                       .by_priority_time
  end

  def charge_rn
    @view_mode = params[:view] || 'staff_tasks'

    if @view_mode == 'floor_view'
      # Load floor view data
      @ed_rooms = Room.ed_rooms.includes(:current_patient)
      @rp_rooms = Room.rp_rooms.includes(:current_patient)
      @current_ed_census = Room.ed_rooms.occupied_rooms.count
      @rp_utilization = Room.rp_rooms.occupied_rooms.count
      @avg_door_to_provider = calculate_avg_door_to_provider
      @avg_ed_los = calculate_avg_ed_los
      @longest_wait = Patient.waiting.maximum(:wait_time_minutes) || 0
      @lwbs_rate = calculate_lwbs_rate
    else
      # Load staff tasks data
      @nursing_tasks = NursingTask.includes(:patient)
                                   .pending_tasks
                                   .by_priority
      @overdue_tasks = @nursing_tasks.overdue
      @nurses = group_tasks_by_nurse
      @medication_timers = load_medication_timers
    end

    @patients = Patient.includes(:vitals, :events).all.by_arrival_time
  end

  def provider
    @patients = Patient.includes(:vitals, :events).with_provider.by_arrival_time
  end
  
  private
  
  def load_dashboard_stats
    @total_waiting = Patient.waiting.count
    @avg_wait_time = Patient.waiting.average(:wait_time_minutes)&.round || 0
    @rp_utilization = calculate_rp_utilization
  end
  
  def calculate_rp_utilization
    total_rp_rooms = Room.rp_rooms.count
    return 0 if total_rp_rooms.zero?
    
    occupied_rp_rooms = Room.rp_rooms.occupied_rooms.count
    ((occupied_rp_rooms.to_f / total_rp_rooms) * 100).round
  end
  
  def calculate_avg_door_to_provider
    # Average time from arrival to provider assignment in minutes
    patients_with_provider = Patient.with_provider.where('arrival_time IS NOT NULL')
    return 0 if patients_with_provider.empty?
    
    45 # Placeholder - in real implementation would calculate from timestamps
  end
  
  def calculate_avg_ed_los
    # Average length of stay in ED in minutes
    ed_patients = Patient.in_ed
    return 0 if ed_patients.empty?
    
    180 # Placeholder - 3 hours average
  end
  
  def calculate_lwbs_rate
    # Left Without Being Seen rate as percentage
    2.1 # Placeholder percentage
  end
  
  def group_tasks_by_nurse
    # Group tasks by assigned nurse
    nurses = {}
    
    NursingTask.pending_tasks.group_by(&:assigned_to).each do |nurse_type, tasks|
      nurse_name = case nurse_type
                   when 'RP RN' then 'Emily Thompson'
                   when 'ED RN' then 'David Kim'
                   else 'Unassigned'
                   end
      
      nurses[nurse_name] = {
        tasks: tasks.sort_by { |t| [-t.priority, t.created_at] },
        total_time: tasks.sum { |t| t.elapsed_time }
      }
    end
    
    nurses
  end

  def load_medication_timers
    # Load all active medication orders (not completed)
    medication_orders = CarePathwayOrder.joins(care_pathway: :patient)
                                        .includes(care_pathway: :patient)
                                        .where(order_type: :medication)
                                        .where.not(status: [:administered])
                                        .order(:ordered_at)

    medication_orders.map do |order|
      patient = order.care_pathway.patient
      elapsed_minutes = order.status_updated_at ? ((Time.current - order.status_updated_at) / 60).round : 0

      # Determine timer status based on elapsed time
      timer_status = if elapsed_minutes <= 5
                      'timer-green'
                    elsif elapsed_minutes <= 10
                      'timer-yellow'
                    else
                      'timer-red'
                    end

      {
        patient_name: patient.full_name,
        room: patient.room_number || 'Unassigned',
        medication_name: order.name,
        ordered_at: order.ordered_at&.strftime("%l:%M %p"),
        elapsed_time: elapsed_minutes,
        current_status: order.status_label,
        status_class: timer_status,
        order_id: order.id,
        patient_id: patient.id,
        care_pathway_id: order.care_pathway_id
      }
    end
  end
end
