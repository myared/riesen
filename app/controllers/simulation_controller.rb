class SimulationController < ApplicationController
  # Define valid timestamp fields as a constant for security
  VALID_TIMESTAMP_FIELDS = %w[
    collected_at in_lab_at resulted_at administered_at
    exam_started_at exam_completed_at status_updated_at
  ].freeze

  def add_patient
    patient = PatientGenerator.new.generate.tap(&:save!)
    PatientArrivalService.new(patient).process

    redirect_back fallback_location: root_path,
                  notice: "Patient #{patient.full_name} added successfully"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: root_path,
                  alert: e.record.errors.full_messages.to_sentence
  end

  def fast_forward_time
    time_adjustment = 10.minutes
    updated_count = 0

    # Split into smaller transactions for better performance
    ActiveRecord::Base.transaction do
      # Update patient timers using safe integer value
      seconds = time_adjustment.to_i

      updated_count += Patient.where(location_status: [:needs_room_assignment, :ed_room, :treatment])
                              .update_all("arrival_time = arrival_time - INTERVAL '#{seconds} seconds'")

      updated_count += Patient.where.not(triage_completed_at: nil)
                              .update_all("triage_completed_at = triage_completed_at - INTERVAL '#{seconds} seconds'")

      # Update care pathway order timers
      updated_count += CarePathwayOrder.where.not(ordered_at: nil)
                                       .update_all("ordered_at = ordered_at - INTERVAL '#{seconds} seconds'")

      # Update other timestamp fields with validation
      VALID_TIMESTAMP_FIELDS.each do |field|
        # Verify field exists in the model for security
        next unless CarePathwayOrder.column_names.include?(field)

        updated_count += CarePathwayOrder.where.not(field => nil)
                                         .update_all("#{field} = #{field} - INTERVAL '#{seconds} seconds'")
      end
    end

    # Process timer expirations in a separate operation
    process_timer_expirations

    redirect_back fallback_location: root_path,
                  notice: "Fast forwarded all timers by 10 minutes (#{updated_count} records updated)"
  rescue => e
    Rails.logger.error "Failed to fast forward time: #{e.class}: #{e.message}"
    redirect_back fallback_location: root_path,
                  alert: "Failed to fast forward time. Please try again."
  end

  private

  def process_timer_expirations
    # Update timer statuses for all care pathway orders
    CarePathwayOrder.find_each do |order|
      # Recalculate timer status based on new timestamps
      previous_timer_status = order.timer_status

      # Calculate the duration based on current status and timestamps
      current_time = Time.current
      previous_timestamp = case order.status.to_sym
      when :ordered
        order.ordered_at
      when :collected
        order.collected_at
      when :in_lab
        order.in_lab_at
      when :resulted
        order.resulted_at
      when :administered
        order.administered_at
      when :exam_started
        order.exam_started_at
      when :exam_completed
        order.exam_completed_at
      else
        order.status_updated_at
      end

      if previous_timestamp
        duration_minutes = ((current_time - previous_timestamp) / 60).round
        new_timer_status = order.send(:calculate_timer_status, duration_minutes)

        # Update the timer status and duration if changed
        if new_timer_status != previous_timer_status
          begin
            order.update!(
              timer_status: new_timer_status,
              last_status_duration_minutes: duration_minutes
            )

            Event.create!(
              patient: order.care_pathway.patient,
              action: "Order timer status changed",
              details: "Order '#{order.name}' timer changed from #{previous_timer_status} to #{new_timer_status} (#{duration_minutes} min) - Fast forward",
              performed_by: "System",
              time: Time.current,
              category: "clinical"
            )
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.error "Failed to update timer status for Order ID: #{order.id}: #{e.record.errors.full_messages.join(', ')}"
          rescue ActiveRecord::RecordNotFound => e
            Rails.logger.warn "Order not found during timer update: #{order.id}"
          rescue => e
            Rails.logger.error "Unexpected error updating timer for Order ID: #{order.id}: #{e.class}: #{e.message}"
            raise e if Rails.env.development?
          end
        end
      end
    end

    # Check for expired patient wait timers
    Patient.where(location_status: [:needs_room_assignment, :ed_room]).find_each do |patient|
      # Calculate total wait time since arrival for event creation
      wait_time = if patient.arrival_time
                    ((Time.current - patient.arrival_time) / 60).round
                  else
                    0
                  end

      # Create events for patients waiting over thresholds
      if wait_time > 120 && !patient.events.where(action: "Wait time exceeded 120 minutes").where("time > ?", 1.hour.ago).exists?
        Event.create!(
          patient: patient,
          action: "Wait time exceeded 120 minutes",
          details: "Patient has been waiting for #{wait_time} minutes",
          performed_by: "System",
          time: Time.current,
          category: "administrative"
        )
      elsif wait_time > 60 && !patient.events.where(action: "Wait time exceeded 60 minutes").where("time > ?", 1.hour.ago).exists?
        Event.create!(
          patient: patient,
          action: "Wait time exceeded 60 minutes",
          details: "Patient has been waiting for #{wait_time} minutes",
          performed_by: "System",
          time: Time.current,
          category: "administrative"
        )
      end
    end
  end
end