class ApplicationSetting < ApplicationRecord
  # Singleton pattern - only one setting record should exist
  def self.current
    instance
  end

  def self.instance
    first_or_create!
  end

  # ESI target helper
  def esi_target_for(esi_level)
    case esi_level
    when 1 then esi_1_target
    when 2 then esi_2_target
    when 3 then esi_3_target
    when 4 then esi_4_target
    when 5 then esi_5_target
    else 30 # Default fallback
    end
  end

  # Timer target helper for orders
  def timer_target_for(order_type, status)
    case order_type.to_s
    when 'medicine', 'medication'
      case status.to_s
      when 'ordered' then medicine_ordered_target
      when 'administered', 'completed' then medicine_administered_target
      else medicine_ordered_target
      end
    when 'lab'
      case status.to_s
      when 'ordered' then lab_ordered_target
      when 'collected' then lab_collected_target
      when 'in_lab' then lab_in_lab_target
      when 'resulted', 'completed' then lab_resulted_target
      else lab_ordered_target
      end
    when 'imaging'
      case status.to_s
      when 'ordered' then imaging_ordered_target
      when 'exam_started' then imaging_exam_started_target
      when 'exam_completed' then imaging_exam_completed_target
      when 'resulted', 'completed' then imaging_resulted_target
      else imaging_ordered_target
      end
    else
      30 # Default fallback
    end
  end

  # Calculate warning threshold in minutes
  def warning_threshold_minutes(target_minutes)
    (target_minutes * warning_threshold_percentage / 100.0).round
  end

  # Calculate critical threshold in minutes
  def critical_threshold_minutes(target_minutes)
    (target_minutes * critical_threshold_percentage / 100.0).round
  end

  # Validation
  validates :ed_rooms, :rp_rooms, presence: true, numericality: { greater_than: 0 }
  validates :esi_1_target, :esi_2_target, :esi_3_target, :esi_4_target, :esi_5_target,
            presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :medicine_ordered_target, :medicine_administered_target,
            :lab_ordered_target, :lab_collected_target, :lab_in_lab_target, :lab_resulted_target,
            :imaging_ordered_target, :imaging_exam_started_target, :imaging_exam_completed_target, :imaging_resulted_target,
            presence: true, numericality: { greater_than: 0 }
  validates :warning_threshold_percentage, :critical_threshold_percentage,
            presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
end
