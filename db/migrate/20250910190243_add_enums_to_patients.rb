class AddEnumsToPatients < ActiveRecord::Migration[8.0]
  def change
    add_column :patients, :location_status, :integer, default: 0
    add_index :patients, :location_status
    
    # Migrate existing string location data to enum
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE patients 
          SET location_status = CASE location
            WHEN 'Waiting Room' THEN 0
            WHEN 'Triage' THEN 1
            WHEN 'Results Pending' THEN 2
            WHEN 'ED Room' THEN 3
            WHEN 'Treatment' THEN 4
            ELSE 0
          END
        SQL
      end
    end
  end
end
