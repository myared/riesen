class Patient < ApplicationRecord
  # ESI level descriptions (removed hardcoded targets - now in ApplicationSetting)

  # ESI Level descriptions
  ESI_DESCRIPTIONS = {
    1 => "Resuscitation",
    2 => "Emergent",
    3 => "Urgent",
    4 => "Less Urgent",
    5 => "Non-Urgent"
  }.freeze

  # Valid pain score range
  PAIN_SCORE_RANGE = (1..10).freeze

  # Timer thresholds (in minutes)
  ROOM_ASSIGNMENT_TARGET = 20   # Target time for room assignment

  # Enum for location status
  enum :location_status, {
    waiting_room: 0,
    triage: 1,
    needs_room_assignment: 2,
    results_pending: 3,
    ed_room: 4,
    treatment: 5,
    discharged: 6,
    pending_transfer: 7
  }, prefix: :location

  has_many :vitals, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :care_pathways, dependent: :destroy

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :mrn, presence: true, uniqueness: true
  validates :esi_level, inclusion: { in: (1..5) }, allow_nil: true
  validates :pain_score, inclusion: { in: PAIN_SCORE_RANGE }, allow_nil: true

  # Scopes
  scope :active, -> { where(discharged: false) }
  scope :discharged_patients, -> { where(discharged: true) }
  scope :waiting, -> { location_waiting_room }
  scope :in_triage, -> { where(location_status: [ :waiting_room, :triage, :pending_transfer ]) }
  scope :in_ed, -> { where(location_status: [ :ed_room, :treatment ]) }
  scope :with_provider, -> { where.not(provider: nil) }
  scope :critical, -> { where(esi_level: [ 1, 2 ]) }

  # New scopes for dashboard organization
  scope :by_arrival_time, -> { order(arrival_time: :asc) }

  scope :by_priority_time, -> {
    needs_room_status = location_statuses[:needs_room_assignment]
    order(
      Arel.sql(
        "CASE
          WHEN location_status = #{connection.quote(needs_room_status)}
          THEN COALESCE(triage_completed_at, arrival_time)
          ELSE arrival_time
        END ASC"
      )
    )
  }

  scope :needs_rp_assignment, -> {
    active.where(location_status: :needs_room_assignment, rp_eligible: true)
  }

  scope :needs_ed_assignment, -> {
    active.where(location_status: :needs_room_assignment, rp_eligible: false)
  }

  scope :in_results_pending, -> {
    active.where(location_status: :results_pending)
  }

  scope :in_ed_treatment, -> {
    active.where(location_status: [ :ed_room, :treatment ])
  }

  scope :pending_transfer_to_rp, -> {
    active.where(location_status: :pending_transfer, rp_eligible: true)
  }

  scope :pending_transfer_to_ed, -> {
    active.where(location_status: :pending_transfer, rp_eligible: false)
  }

  scope :rp_eligible_in_waiting_room, -> {
    active.where(location_status: :waiting_room, rp_eligible: true)
  }

  scope :rp_eligible_pending_from_ed, -> {
    active
      .where(rp_eligible: true)
      .where.not(rp_eligibility_started_at: nil)
      .where(location_status: [ :ed_room, :treatment ])
  }

  def full_name
    "#{first_name} #{last_name}"
  end

  def active_care_pathway
    # Determine the expected pathway type based on location
    expected_type = case location_status
    when "waiting_room", "triage"
                     "triage"
    when "needs_room_assignment", "results_pending", "ed_room", "treatment"
                     "emergency_room"
    else
                     "triage"
    end

    # Return the most recent active pathway of the expected type
    care_pathways.where(
      pathway_type: expected_type,
      status: [ :not_started, :in_progress ]
    ).order(created_at: :desc).first
  end

  def latest_vital
    vitals.order(recorded_at: :desc).first
  end

  def wait_progress_percentage
    timer = longest_wait_timer
    return 0 unless timer

    current_wait = timer[:time].to_f

    # Determine target based on timer type
    target = if timer[:type] == :order && timer[:order]
      order = timer[:order]
      if order.order_type_medication?
        10  # Medication target is 10 minutes (yellow threshold)
      else
        40  # Lab/Imaging target is 40 minutes (yellow threshold)
      end
    else
      esi_target_minutes
    end

    return 100 if target.zero?
    [ (current_wait / target * 100).round, 100 ].min
  end

  def esi_target_minutes
    return 30 unless esi_level
    ApplicationSetting.current.esi_target_for(esi_level)
  end

  def esi_target_label
    timer = longest_wait_timer

    if timer && timer[:type] == :order && timer[:order]
      order = timer[:order]
      settings = ApplicationSetting.current
      target = settings.timer_target_for(order.order_type, order.status)
      "#{target}m target"
    elsif esi_level == 1 && esi_target_minutes == 0
      "Immediate"
    else
      "#{esi_target_minutes}m target"
    end
  end

  def esi_description
    ESI_DESCRIPTIONS[esi_level]
  end

  def overdue?
    wait_time_minutes > esi_target_minutes
  end

  def wait_status
    timer = longest_wait_timer
    return :green unless timer

    current_wait = timer[:time]
    settings = ApplicationSetting.current

    # Determine thresholds based on timer type
    if timer[:type] == :order && timer[:order]
      # Use order-specific thresholds from settings
      order = timer[:order]
      target = settings.timer_target_for(order.order_type, order.status)
      warning_threshold = settings.warning_threshold_minutes(target)
      critical_threshold = settings.critical_threshold_minutes(target)

      if current_wait <= warning_threshold
        :green
      elsif current_wait <= critical_threshold
        :yellow
      else
        :red
      end
    else
      # Use ESI-based thresholds for arrival/room assignment
      target = esi_target_minutes
      warning_threshold = settings.warning_threshold_minutes(target)
      critical_threshold = settings.critical_threshold_minutes(target)

      if current_wait <= warning_threshold
        :green
      elsif current_wait <= critical_threshold
        :yellow
      else
        :red
      end
    end
  end

  def wait_status_class
    case wait_status
    when :green
      "wait-green"
    when :yellow
      "wait-yellow"
    when :red
      "wait-red"
    else
      ""
    end
  end

  def critical?
    esi_level.in?([ 1, 2 ])
  end

  def location_needs_room_assignment?
    location_status == "needs_room_assignment"
  end

  # Calculate wait time based on the longest active timer
  def wait_time_minutes
    timers = []

    # Only check arrival/triage timers if patient is not yet in a room
    if !location_ed_room? && !location_treatment? && !location_results_pending?
      # Check arrival time if not yet triaged
      if arrival_time && !triage_completed_at
        timers << {
          time: ((Time.current - arrival_time) / 60).round,
          type: :arrival,
          order: nil
        }
      end

      # Check triage completion time if waiting for room
      if triage_completed_at && location_needs_room_assignment?
        timers << {
          time: ((Time.current - triage_completed_at) / 60).round,
          type: :room_assignment,
          order: nil
        }
      end
    end

    # Check all active care pathway orders
    care_pathways.each do |pathway|
      pathway.care_pathway_orders.where.not(status: [ :resulted, :administered, :exam_completed ]).each do |order|
        # Get the appropriate timestamp based on order status
        timestamp = case order.status.to_sym
        when :ordered
          order.ordered_at
        when :collected
          order.collected_at
        when :in_lab
          order.in_lab_at
        when :exam_started
          order.exam_started_at
        else
          order.status_updated_at || order.ordered_at
        end

        if timestamp
          timers << {
            time: ((Time.current - timestamp) / 60).round,
            type: :order,
            order: order
          }
        end
      end
    end

    # Return the longest timer value, or 0 if no timers
    longest_timer = timers.max_by { |t| t[:time] }
    @longest_wait_timer = longest_timer  # Store for other methods to use
    longest_timer ? longest_timer[:time] : 0
  end

  # Get the longest waiting order/task details
  def longest_wait_timer
    wait_time_minutes if @longest_wait_timer.nil?  # Calculate if not already done
    @longest_wait_timer
  end

  # Get top pending tasks with their timer status for simplified display
  def top_pending_tasks(limit = 4)
    tasks = []

    # Check if patient is at 100% care pathway completion and show Ready for Dispo or Ready for Checkout
    if active_care_pathway&.progress_percentage == 100
      if ready_for_checkout?
        # Patient has been marked ready for checkout after clicking Discharge
        elapsed_minutes = ready_for_checkout_at ? ((Time.current - ready_for_checkout_at) / 60).round : 0
        tasks << {
          name: "Ready for Checkout",
          type: :ready_for_checkout,
          elapsed_time: elapsed_minutes,
          status: calculate_task_status(elapsed_minutes, 20), # 20 minute target
          care_pathway_id: active_care_pathway.id
        }
      else
        # Patient is at 100% but not yet discharged - show Ready for Dispo
        # Calculate time since all endpoints were achieved
        pathway = active_care_pathway
        last_achieved_time = pathway.care_pathway_clinical_endpoints.maximum(:achieved_at) || Time.current
        elapsed_minutes = ((Time.current - last_achieved_time) / 60).round
        tasks << {
          name: "Ready for Dispo",
          type: :ready_for_dispo,
          elapsed_time: elapsed_minutes,
          status: calculate_task_status(elapsed_minutes, 20), # 20 minute target
          care_pathway_id: pathway.id
        }
      end
      return tasks # Return early since we only show one task at 100% completion
    end

    # For patients in triage/waiting room, show their current triage step
    if location_waiting_room? || location_triage? || location_pending_transfer? || location_needs_room_assignment?
      triage_pathway = care_pathways.pathway_type_triage.where(status: [ :not_started, :in_progress ]).first

      if triage_pathway
        current_step = triage_pathway.current_triage_step

        if current_step
          # Determine elapsed time and target based on step
          case current_step.name
          when "Check-In"
            # Timer starts from arrival time
            if arrival_time
              elapsed_minutes = ((Time.current - arrival_time) / 60).round
              target_minutes = 10 # 10 minutes for check-in
              tasks << {
                name: "Check In",
                type: :check_in,
                elapsed_time: elapsed_minutes,
                status: calculate_task_status(elapsed_minutes, target_minutes),
                care_pathway_id: triage_pathway.id
              }
            end
          when "Intake"
            # Timer starts from check-in completion
            check_in_step = triage_pathway.care_pathway_steps.find_by(name: "Check-In")
            if check_in_step&.completed_at
              elapsed_minutes = ((Time.current - check_in_step.completed_at) / 60).round
              target_minutes = 10 # 10 minutes for intake
              tasks << {
                name: "Intake",
                type: :intake,
                elapsed_time: elapsed_minutes,
                status: calculate_task_status(elapsed_minutes, target_minutes),
                care_pathway_id: triage_pathway.id
              }
            end
          when "Bed Assignment"
            # Timer starts from intake completion
            intake_step = triage_pathway.care_pathway_steps.find_by(name: "Intake")
            if intake_step&.completed_at
              elapsed_minutes = ((Time.current - intake_step.completed_at) / 60).round
              target_minutes = esi_target_minutes # ESI-based target
              tasks << {
                name: "Bed Assignment",
                type: :bed_assignment,
                elapsed_time: elapsed_minutes,
                status: calculate_task_status(elapsed_minutes, target_minutes),
                care_pathway_id: triage_pathway.id
              }
            end
          when "Pending Transfer"
            # Timer starts from bed assignment completion
            bed_assignment_step = triage_pathway.care_pathway_steps.find_by(name: "Bed Assignment")
            if bed_assignment_step&.completed_at
              elapsed_minutes = ((Time.current - bed_assignment_step.completed_at) / 60).round
              target_minutes = esi_target_minutes # ESI-based target
              tasks << {
                name: "Pending Transfer",
                type: :pending_transfer,
                elapsed_time: elapsed_minutes,
                status: calculate_task_status(elapsed_minutes, target_minutes),
                care_pathway_id: triage_pathway.id
              }
            end
          end
        end
      elsif arrival_time && !triage_completed_at
        # Fallback for patients without a triage pathway yet
        elapsed_minutes = ((Time.current - arrival_time) / 60).round
        tasks << {
          name: "Triage",
          type: :triage,
          elapsed_time: elapsed_minutes,
          status: calculate_task_status(elapsed_minutes, 10), # Default 10 minutes
          care_pathway_id: nil
        }
      end
    end

    if rp_transfer_pending?
      elapsed_minutes = rp_eligibility_time_minutes
      tasks << {
        name: "RP Eligible",
        type: :rp_eligible,
        elapsed_time: elapsed_minutes,
        status: calculate_task_status(elapsed_minutes, 20, :rp_eligible),
        care_pathway_id: active_care_pathway&.id
      }
    end

    # Check all active care pathways for procedures, clinical endpoints, and orders
    care_pathways.each do |pathway|
      # Add pending procedures as tasks with 20-minute timer
      pathway.care_pathway_procedures.pending.each do |procedure|
        if procedure.created_at
          elapsed_minutes = ((Time.current - procedure.created_at) / 60).round
          tasks << {
            name: "🔧 #{procedure.name}",
            type: :procedure,
            elapsed_time: elapsed_minutes,
            status: calculate_task_status(elapsed_minutes, 20, :procedure), # 20-minute timer with fixed thresholds
            care_pathway_id: pathway.id,
            procedure_id: procedure.id
          }
        end
      end

      # Add pending clinical endpoints as tasks with 20-minute timer
      pathway.care_pathway_clinical_endpoints.pending.each do |endpoint|
        if endpoint.created_at
          elapsed_minutes = ((Time.current - endpoint.created_at) / 60).round
          tasks << {
            name: "🎯 #{endpoint.name}",
            type: :clinical_endpoint,
            elapsed_time: elapsed_minutes,
            status: calculate_task_status(elapsed_minutes, 20, :clinical_endpoint), # 20-minute timer with fixed thresholds
            care_pathway_id: pathway.id,
            endpoint_id: endpoint.id
          }
        end
      end

      # Add orders that aren't completed
      pathway.care_pathway_orders.where.not(status: [ :resulted, :administered, :exam_completed ]).each do |order|
        # Get the appropriate timestamp based on order status
        timestamp = case order.status.to_sym
        when :ordered
          order.ordered_at
        when :collected
          order.collected_at
        when :in_lab
          order.in_lab_at
        when :exam_started
          order.exam_started_at
        else
          order.status_updated_at || order.ordered_at
        end

        if timestamp
          elapsed_minutes = ((Time.current - timestamp) / 60).round
          settings = ApplicationSetting.current
          target = settings.timer_target_for(order.order_type, order.status)

          tasks << {
            name: "#{order.type_icon} #{order.name} - #{order.status_label}",
            type: :order,
            elapsed_time: elapsed_minutes,
            status: calculate_task_status(elapsed_minutes, target),
            care_pathway_id: pathway.id,
            order_id: order.id
          }
        end
      end
    end

    # Sort by status priority (red > yellow > green) then by elapsed time
    tasks.sort_by { |t| [ status_priority(t[:status]), -t[:elapsed_time] ] }.first(limit)
  end

  def highest_priority_task_status
    # Get the highest priority task status for sorting purposes
    # Returns 0 for red, 1 for yellow, 2 for green, 3 for no tasks
    tasks = top_pending_tasks(100) # Get all tasks to find the highest priority
    return 3 if tasks.empty?

    # Find the highest priority status
    tasks.map { |t| status_priority(t[:status]) }.min
  end

  # Override setters to clear cache when relevant attributes change
  def arrival_time=(value)
    @longest_wait_timer = nil if value != arrival_time
    super
  end

  def triage_completed_at=(value)
    @longest_wait_timer = nil if value != triage_completed_at
    super
  end

  def location_status=(value)
    @longest_wait_timer = nil if value != location_status
    super
  end

  def intake_complete?
    triage_completed_at.present? && esi_level.present?
  end

  def check_in_and_intake_complete?
    # Check if the patient has an active triage pathway with both check-in and intake completed
    pathway = care_pathways.pathway_type_triage.where(status: [ :not_started, :in_progress ]).first
    return false unless pathway

    check_in_step = pathway.care_pathway_steps.find_by(name: "Check-In")
    intake_step = pathway.care_pathway_steps.find_by(name: "Intake")

    check_in_step&.completed? && intake_step&.completed?
  end

  def all_triage_steps_complete?
    # Check if all triage pathway steps are completed (including bed assignment)
    pathway = care_pathways.pathway_type_triage.where(status: [ :not_started, :in_progress ]).first
    return false unless pathway

    check_in_step = pathway.care_pathway_steps.find_by(name: "Check-In")
    intake_step = pathway.care_pathway_steps.find_by(name: "Intake")
    bed_assignment_step = pathway.care_pathway_steps.find_by(name: "Bed-Assignment")

    check_in_step&.completed? && intake_step&.completed? && bed_assignment_step&.completed?
  end

  def rp_eligibility_time_minutes
    return 0 unless rp_eligibility_started_at && rp_eligible?
    ((Time.current - rp_eligibility_started_at) / 60).round
  end

  def rp_eligibility_status
    return :green unless rp_eligible? && rp_eligibility_started_at

    minutes = rp_eligibility_time_minutes
    settings = ApplicationSetting.current
    target = settings.esi_target_for(esi_level || 3)  # Default to ESI 3 if not set

    warning_threshold = settings.warning_threshold_minutes(target)
    critical_threshold = settings.critical_threshold_minutes(target)

    if minutes <= warning_threshold
      :green
    elsif minutes <= critical_threshold
      :yellow
    else
      :red
    end
  end

  def rp_transfer_pending?
    rp_eligible? && rp_eligibility_started_at.present? && !location_results_pending?
  end

  def room_assignment_started_at
    return nil unless location_needs_room_assignment?
    triage_completed_at || updated_at
  end

  def time_waiting_for_room
    return 0 unless room_assignment_started_at
    ((Time.current - room_assignment_started_at) / 60).round
  end

  def room_assignment_status
    return :green if !location_needs_room_assignment?

    wait_time = time_waiting_for_room
    target = ROOM_ASSIGNMENT_TARGET

    if wait_time <= target
      :green  # On time (under 20 minutes)
    elsif wait_time <= (target * 2)
      :yellow  # Warning (20-40 minutes)
    else
      :red  # Critical (over 40 minutes)
    end
  end

  def room_assignment_status_class
    case room_assignment_status
    when :green
      "timer-green"
    when :yellow
      "timer-yellow"
    when :red
      "timer-red"
    else
      ""
    end
  end

  def display_location
    case location_status
    when "waiting_room"
      "Waiting Room"
    when "triage"
      "Triage"
    when "pending_transfer"
      "Pending Transfer"
    when "results_pending"
      "RP"
    when "ed_room", "treatment"
      "ED"
    when "needs_room_assignment"
      rp_eligible? ? "RP" : "ED"
    when "discharged"
      "Discharged"
    else
      "Waiting Room"
    end
  end

  def display_room
    return "WR" unless room_number.present?
    return room_number if room_number.match?(/^[RE]\d/)
    "??"
  end

  def can_be_discharged?
    # Patient can be discharged if:
    # 1. They have an ER care pathway
    # 2. All clinical endpoints are achieved
    # 3. There is at least one clinical endpoint
    # 4. They haven't already been marked for checkout
    pathway = active_care_pathway
    return false unless pathway&.pathway_type_emergency_room?
    return false if ready_for_checkout? # Already in checkout process

    endpoints = pathway.care_pathway_clinical_endpoints
    endpoints.any? && endpoints.all?(&:achieved?)
  end

  def can_be_checked_out?
    # Patient can be checked out if they're marked ready for checkout
    ready_for_checkout?
  end

  def needs_clinical_endpoints?
    # Check if patient needs clinical endpoints defined
    pathway = active_care_pathway
    return false unless pathway&.pathway_type_emergency_room?

    pathway.care_pathway_clinical_endpoints.empty?
  end

  # Mark patient as ready for checkout (first step of discharge)
  def mark_ready_for_checkout!(performed_by:)
    transaction do
      # Check if patient can be discharged
      unless can_be_discharged?
        raise NotDischargeable, "Patient cannot be discharged. Ensure all clinical endpoints are achieved."
      end

      # Update patient status to ready for checkout
      update!(
        ready_for_checkout: true,
        ready_for_checkout_at: Time.current
      )

      # Log the event
      Event.create!(
        patient: self,
        action: "Patient ready for checkout",
        details: "Patient marked as ready for checkout from #{display_location}",
        performed_by: performed_by,
        time: Time.current,
        category: "administrative"
      )
    end
  end

  # Complete the checkout and discharge the patient (second step)
  def checkout!(performed_by:)
    transaction do
      # Check if patient can be checked out
      unless can_be_checked_out?
        raise NotDischargeable, "Patient is not ready for checkout."
      end

      previous_location = display_location
      care_pathway_to_complete = active_care_pathway

      # Release any room currently assigned to the patient so it becomes available
      room = Room.find_by(current_patient: self)
      room ||= Room.find_by(number: room_number) if room_number.present?
      room&.release

      # Update patient discharge status
      update!(
        discharged: true,
        discharged_at: Time.current,
        discharged_by: performed_by,
        ready_for_checkout: false, # Clear the checkout flag
        location_status: :discharged
      )

      # Mark care pathway as completed
      if care_pathway_to_complete
        care_pathway_to_complete.update!(
          status: :completed,
          completed_at: Time.current,
          completed_by: performed_by
        )
      end

      # Log the discharge event
      Event.create!(
        patient: self,
        action: "Patient checked out",
        details: "Patient checked out and discharged from #{previous_location}",
        performed_by: performed_by,
        time: Time.current,
        category: "administrative"
      )
    end
  end

  # Legacy discharge method - now redirects to the two-step process
  def discharge!(performed_by:)
    mark_ready_for_checkout!(performed_by: performed_by)
  end

  # Custom exception for discharge failures
  class NotDischargeable < StandardError; end

  private

  def calculate_task_status(elapsed_minutes, target_minutes, task_type = nil)
    # Special handling for procedures and clinical endpoints with fixed thresholds
    if [:procedure, :clinical_endpoint].include?(task_type) || target_minutes == 20
      # For 20-minute tasks: green 0-16, yellow 16-20, red >20
      if elapsed_minutes <= 16
        :green
      elsif elapsed_minutes <= 20
        :yellow
      else
        :red
      end
    else
      # Use existing settings for other task types
      settings = ApplicationSetting.current
      warning_threshold = settings.warning_threshold_minutes(target_minutes)
      critical_threshold = settings.critical_threshold_minutes(target_minutes)

      if elapsed_minutes <= warning_threshold
        :green
      elsif elapsed_minutes <= critical_threshold
        :yellow
      else
        :red
      end
    end
  end

  def status_priority(status)
    case status
    when :red then 0
    when :yellow then 1
    when :green then 2
    else 3
    end
  end
end
