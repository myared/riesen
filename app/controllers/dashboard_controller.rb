class DashboardController < ApplicationController
  before_action :load_dashboard_stats

  def triage
    session[:current_role] = 'triage'
    @patients = Patient.includes(:vitals, :events).in_triage.by_arrival_time
    wait_times = @patients.map(&:wait_time_minutes).compact
    @avg_wait_time = wait_times.any? ? (wait_times.sum / wait_times.size.to_f).round : 0
  end

  def rp
    # Clear provider role
    session[:current_role] = 'rp'
    # Include both patients in RP and those waiting for RP room assignment
    # Sort by wait time with highest minutes at top
    @patients = Patient.includes(:vitals, :events, :care_pathways)
                       .in_results_pending
                       .or(Patient.needs_rp_assignment)
                       .to_a
                       .sort_by { |p| -p.wait_time_minutes }
  end

  def ed_rn
    # Clear provider role
    session[:current_role] = 'ed_rn'
    # Include both patients in ED and those waiting for ED room assignment
    # Sort by wait time with highest minutes at top
    @patients = Patient.includes(:vitals, :events, :care_pathways)
                       .in_ed_treatment
                       .or(Patient.needs_ed_assignment)
                       .to_a
                       .sort_by { |p| -p.wait_time_minutes }
  end

  def charge_rn
    # Clear provider role
    session[:current_role] = 'charge_rn'
    @view_mode = params[:view] || "staff_tasks"

    if @view_mode == "floor_view"
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
      @active_orders = load_active_orders
      @medication_timers = load_medication_timers
      nurses_unsorted = group_tasks_by_nurse  # Must be called after loading active_orders
      # Sort nurses by total workload (cumulative minutes) in descending order
      @nurses = nurses_unsorted.sort_by { |_name, data| -data[:total_time] }.to_h
    end

    @patients = Patient.includes(:vitals, :events).all.by_arrival_time
  end

  def provider
    # Set the role in session for access control
    session[:current_role] = 'provider'

    # Show all patients in RP (Results Pending) or ED RN (ED Room/Treatment)
    @patients = Patient.includes(:vitals, :events, :care_pathways)
                       .in_results_pending
                       .or(Patient.in_ed_treatment)
                       .by_arrival_time
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
    patients_with_provider = Patient.with_provider.where("arrival_time IS NOT NULL")
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

    # Initialize nurses with empty arrays
    nurses["Emily Thompson"] = { tasks: [], orders: [], total_time: 0 }
    nurses["David Kim"] = { tasks: [], orders: [], total_time: 0 }

    # First, get nursing tasks
    NursingTask.pending_tasks.group_by(&:assigned_to).each do |nurse_type, tasks|
      nurse_name = case nurse_type
      when "RP RN" then "Emily Thompson"
      when "ED RN" then "David Kim"
      else "Unassigned"
      end

      # Sort by color priority (red > yellow > green), then by elapsed time
      sorted_tasks = tasks.sort_by { |t| [ -t.sort_priority, -t.elapsed_time ] }

      if nurses[nurse_name]
        nurses[nurse_name][:tasks] = sorted_tasks
        nurses[nurse_name][:total_time] = sorted_tasks.sum { |t| t.elapsed_time }
      else
        # Handle unassigned tasks
        nurses[nurse_name] = {
          tasks: sorted_tasks,
          orders: [],
          total_time: sorted_tasks.sum { |t| t.elapsed_time }
        }
      end
    end

    # Now integrate orders assigned to nurses
    if @active_orders
      @active_orders.each do |order|
        # Use assigned_to field if available, otherwise use logic based on order type
        nurse_assignment = if order[:assigned_to].present?
                            case order[:assigned_to]
                            when "ED RN" then "David Kim"
                            when "RP RN", "RN" then "Emily Thompson"
                            else nil
                            end
        elsif order[:order_type] == "Medication"
                            "David Kim"  # ED RN for medications
        else
                            "Emily Thompson"  # RP RN for other orders
        end

        # Skip if no valid nurse assignment
        next unless nurse_assignment

        # Add the order to the appropriate nurse's list
        if nurses[nurse_assignment]
          nurses[nurse_assignment][:orders] << order
          nurses[nurse_assignment][:total_time] += order[:elapsed_time]
        else
          # Create a new nurse entry if it doesn't exist
          nurses[nurse_assignment] = {
            tasks: [],
            orders: [ order ],
            total_time: order[:elapsed_time]
          }
        end
      end

      # Sort orders within each nurse by timer status priority
      nurses.each do |_nurse_name, nurse_data|
        nurse_data[:orders] = nurse_data[:orders].sort_by do |order|
          priority = case order[:timer_status]
          when "red" then -3
          when "yellow" then -2
          when "green" then -1
          else 0
          end
          [ priority, -order[:elapsed_time] ]
        end
      end
    end

    nurses
  end

  def load_active_orders
    # Load all active orders (not completed)
    active_orders = CarePathwayOrder.joins(care_pathway: :patient)
                                    .includes(care_pathway: :patient)
                                    .where.not(status: completed_statuses)
                                    .order(:ordered_at)

    active_orders.map do |order|
      build_order_timer(order)
    end
  end

  def completed_statuses
    [ :resulted, :administered ]
  end

  def build_order_timer(order)
    patient = order.care_pathway.patient
    # Use status_updated_at if available, otherwise fall back to ordered_at
    timestamp = order.status_updated_at || order.ordered_at
    elapsed_minutes = timestamp ? ((Time.current - timestamp) / 60).round : 0

    {
      patient_name: patient.full_name,
      room: patient.room_number || "Unassigned",
      order_type: order.order_type.humanize,
      type_icon: order.type_icon,
      order_name: order.name,
      ordered_by: order.ordered_by || "System",
      ordered_at: order.ordered_at&.in_time_zone&.strftime("%l:%M %p PST"),
      elapsed_time: elapsed_minutes,
      current_status: order.status_label,
      timer_status: timer_status_for(elapsed_minutes, order.order_type),
      timer_start_time: timestamp&.iso8601,
      order_id: order.id,
      patient_id: patient.id,
      care_pathway_id: order.care_pathway_id,
      assigned_to: order.assigned_to
    }
  end

  def load_medication_timers
    # Load only medication orders (not completed)
    medication_orders = CarePathwayOrder.joins(care_pathway: :patient)
                                        .includes(care_pathway: :patient)
                                        .where(order_type: :medication)
                                        .where.not(status: [ :administered ])
                                        .order(:ordered_at)

    medication_orders.map do |order|
      patient = order.care_pathway.patient
      timestamp = order.status_updated_at || order.ordered_at
      elapsed_minutes = timestamp ? ((Time.current - timestamp) / 60).round : 0

      {
        patient_name: patient.full_name,
        room: patient.room_number || "Unassigned",
        medication_name: order.name,
        current_status: order.status.to_s.capitalize,
        ordered_at: order.ordered_at&.in_time_zone&.strftime("%l:%M %p PST"),
        elapsed_time: elapsed_minutes,
        timer_status: timer_status_for(elapsed_minutes, "medication"),
        status_class: "timer-#{timer_status_for(elapsed_minutes, 'medication')}",
        order_id: order.id,
        patient_id: patient.id,
        care_pathway_id: order.care_pathway_id
      }
    end
  end

  def timer_status_for(minutes, order_type)
    thresholds = order_type == "medication" ? [ 5, 10 ] : [ 20, 40 ]

    if minutes <= thresholds[0]
      "green"
    elsif minutes <= thresholds[1]
      "yellow"
    else
      "red"
    end
  end
end
