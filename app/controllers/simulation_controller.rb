class SimulationController < ApplicationController
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

    ActiveRecord::Base.transaction do
      # Update patient timers - subtract time from arrival_time to make wait time appear longer
      Patient.where(location_status: [:needs_room_assignment, :ed_room, :treatment])
             .update_all("arrival_time = arrival_time - INTERVAL '#{time_adjustment.to_i} seconds'")

      Patient.where.not(triage_completed_at: nil)
             .update_all("triage_completed_at = triage_completed_at - INTERVAL '#{time_adjustment.to_i} seconds'")

      # Update care pathway order timers
      CarePathwayOrder.where.not(ordered_at: nil)
                      .update_all("ordered_at = ordered_at - INTERVAL '#{time_adjustment.to_i} seconds'")

      # Update other timestamp fields where not null
      %w[collected_at in_lab_at resulted_at administered_at exam_started_at exam_completed_at status_updated_at].each do |field|
        CarePathwayOrder.where.not(field => nil)
                        .update_all("#{field} = #{field} - INTERVAL '#{time_adjustment.to_i} seconds'")
      end

      # Process timer expirations and status updates
      process_timer_expirations
    end

    redirect_back fallback_location: root_path,
                  notice: "Fast forwarded all timers by 10 minutes"
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
          rescue => e
            Rails.logger.error "Unexpected error updating timer for Order ID: #{order.id}: #{e.class}: #{e.message}"
          end
        end
      end
    end

    # Check for expired patient wait timers
    Patient.where(location_status: [:needs_room_assignment, :ed_room]).find_each do |patient|
      wait_time = patient.wait_time_minutes

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