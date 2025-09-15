class Patient < ApplicationRecord
  # Constants for ESI level wait time targets (in minutes)
  ESI_WAIT_TARGETS = {
    1 => 0,    # Resuscitation - Immediate
    2 => 10,   # Emergent - 10 minutes
    3 => 30,   # Urgent - 30 minutes
    4 => 30,   # Less Urgent - 30 minutes
    5 => 30    # Non-Urgent - 30 minutes
  }.freeze
  
  # ESI Level descriptions
  ESI_DESCRIPTIONS = {
    1 => 'Resuscitation',
    2 => 'Emergent',
    3 => 'Urgent',
    4 => 'Less Urgent',
    5 => 'Non-Urgent'
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
    discharged: 6
  }, prefix: :location
  
  has_many :vitals, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :care_pathways, dependent: :destroy
  
  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :age, presence: true, numericality: { greater_than: 0 }
  validates :mrn, presence: true, uniqueness: true
  validates :esi_level, inclusion: { in: ESI_WAIT_TARGETS.keys }, allow_nil: true
  validates :pain_score, inclusion: { in: PAIN_SCORE_RANGE }, allow_nil: true
  
  # Scopes
  scope :active, -> { where(discharged: false) }
  scope :discharged_patients, -> { where(discharged: true) }
  scope :waiting, -> { location_waiting_room }
  scope :in_triage, -> { where(location_status: [:waiting_room, :triage]) }
  scope :in_ed, -> { where(location_status: [:ed_room, :treatment]) }
  scope :with_provider, -> { where.not(provider: nil) }
  scope :critical, -> { where(esi_level: [1, 2]) }
  
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
    active.where(location_status: [:ed_room, :treatment])
  }
  
  def full_name
    "#{first_name} #{last_name}"
  end
  
  def active_care_pathway
    # Determine the expected pathway type based on location
    expected_type = case location_status
                   when 'waiting_room', 'triage'
                     'triage'
                   when 'needs_room_assignment', 'results_pending', 'ed_room', 'treatment'
                     'emergency_room'
                   else
                     'triage'
                   end
    
    # Return the most recent active pathway of the expected type
    care_pathways.where(
      pathway_type: expected_type,
      status: [:not_started, :in_progress]
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
    [(current_wait / target * 100).round, 100].min
  end

  def esi_target_minutes
    ESI_WAIT_TARGETS[esi_level] || 30
  end

  def esi_target_label
    timer = longest_wait_timer

    if timer && timer[:type] == :order && timer[:order]
      order = timer[:order]
      if order.order_type_medication?
        "10m target"
      else
        "40m target"
      end
    elsif esi_level == 1
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

    # Determine thresholds based on timer type
    if timer[:type] == :order && timer[:order]
      # Use order-specific thresholds
      order = timer[:order]
      if order.order_type_medication?
        # Medication thresholds: green <= 5, yellow <= 10, red > 10
        if current_wait <= 5
          :green
        elsif current_wait <= 10
          :yellow
        else
          :red
        end
      else
        # Lab/Imaging thresholds: green <= 20, yellow <= 40, red > 40
        if current_wait <= 20
          :green
        elsif current_wait <= 40
          :yellow
        else
          :red
        end
      end
    else
      # Use ESI-based thresholds for arrival/room assignment
      target = esi_target_minutes
      if current_wait <= target
        :green
      elsif current_wait <= (target * 2)
        :yellow
      else
        :red
      end
    end
  end
  
  def wait_status_class
    case wait_status
    when :green
      'wait-green'
    when :yellow
      'wait-yellow'
    when :red
      'wait-red'
    else
      ''
    end
  end
  
  def critical?
    esi_level.in?([1, 2])
  end
  
  def location_needs_room_assignment?
    location_status == 'needs_room_assignment'
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
      pathway.care_pathway_orders.where.not(status: [:resulted, :administered, :exam_completed]).each do |order|
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
      'timer-green'
    when :yellow
      'timer-yellow'
    when :red
      'timer-red'
    else
      ''
    end
  end

  def display_location
    case location_status
    when 'waiting_room'
      'Waiting Room'
    when 'triage'
      'Triage'
    when 'results_pending'
      'RP'
    when 'ed_room', 'treatment'
      'ED'
    when 'needs_room_assignment'
      rp_eligible? ? 'RP' : 'ED'
    else
      'Waiting Room'
    end
  end

  def can_be_discharged?
    # Patient can be discharged if:
    # 1. They have an ER care pathway
    # 2. All clinical endpoints are achieved
    # 3. There is at least one clinical endpoint
    pathway = active_care_pathway
    return false unless pathway&.pathway_type_emergency_room?

    endpoints = pathway.care_pathway_clinical_endpoints
    endpoints.any? && endpoints.all?(&:achieved?)
  end

  def needs_clinical_endpoints?
    # Check if patient needs clinical endpoints defined
    pathway = active_care_pathway
    return false unless pathway&.pathway_type_emergency_room?

    pathway.care_pathway_clinical_endpoints.empty?
  end

  # Discharge the patient with all necessary updates and logging
  def discharge!(performed_by:)
    transaction do
      # Check if patient can be discharged
      unless can_be_discharged?
        raise NotDischargeable, "Patient cannot be discharged. Ensure all clinical endpoints are achieved."
      end

      # Update patient discharge status
      update!(
        discharged: true,
        discharged_at: Time.current,
        discharged_by: performed_by
      )

      # Mark care pathway as completed
      if active_care_pathway
        active_care_pathway.update!(
          status: :completed,
          completed_at: Time.current,
          completed_by: performed_by
        )
      end

      # Log the discharge event
      Event.create!(
        patient: self,
        action: "Patient discharged",
        details: "Patient discharged from #{display_location}",
        performed_by: performed_by,
        time: Time.current,
        category: "administrative"
      )
    end
  end

  # Custom exception for discharge failures
  class NotDischargeable < StandardError; end
end
