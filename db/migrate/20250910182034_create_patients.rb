class CreatePatients < ActiveRecord::Migration[8.0]
  def change
    create_table :patients do |t|
      t.string :first_name
      t.string :last_name
      t.integer :age
      t.string :mrn
      t.string :location
      t.string :provider
      t.text :chief_complaint
      t.integer :esi_level
      t.integer :pain_score
      t.datetime :arrival_time
      t.integer :wait_time_minutes
      t.string :care_pathway
      t.boolean :rp_eligible

      t.timestamps
    end
  end
end
