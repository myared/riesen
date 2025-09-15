class CreateApplicationSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :application_settings do |t|
      # Hospital Size Configuration
      t.integer :ed_rooms, default: 20, null: false
      t.integer :rp_rooms, default: 12, null: false

      # ESI-based Triage Timers (in minutes)
      t.integer :esi_1_target, default: 0, null: false
      t.integer :esi_2_target, default: 10, null: false
      t.integer :esi_3_target, default: 30, null: false
      t.integer :esi_4_target, default: 60, null: false
      t.integer :esi_5_target, default: 120, null: false

      # Medicine Order Timers (2 phases)
      t.integer :medicine_ordered_target, default: 30, null: false
      t.integer :medicine_administered_target, default: 60, null: false

      # Lab Order Timers (4 phases)
      t.integer :lab_ordered_target, default: 15, null: false
      t.integer :lab_collected_target, default: 30, null: false
      t.integer :lab_in_lab_target, default: 45, null: false
      t.integer :lab_resulted_target, default: 60, null: false

      # Imaging Order Timers (4 phases)
      t.integer :imaging_ordered_target, default: 20, null: false
      t.integer :imaging_exam_started_target, default: 40, null: false
      t.integer :imaging_exam_completed_target, default: 60, null: false
      t.integer :imaging_resulted_target, default: 80, null: false

      # Warning and Critical Thresholds (as percentages)
      t.integer :warning_threshold_percentage, default: 75, null: false
      t.integer :critical_threshold_percentage, default: 100, null: false

      t.timestamps
    end
  end
end
