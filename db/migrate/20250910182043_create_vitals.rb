class CreateVitals < ActiveRecord::Migration[8.0]
  def change
    create_table :vitals do |t|
      t.references :patient, null: false, foreign_key: true
      t.integer :heart_rate
      t.integer :blood_pressure_systolic
      t.integer :blood_pressure_diastolic
      t.integer :respiratory_rate
      t.float :temperature
      t.integer :spo2
      t.float :weight
      t.datetime :recorded_at

      t.timestamps
    end
  end
end
