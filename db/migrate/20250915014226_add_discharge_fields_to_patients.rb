class AddDischargeFieldsToPatients < ActiveRecord::Migration[8.0]
  def change
    add_column :patients, :discharged, :boolean, default: false, null: false
    add_column :patients, :discharged_at, :datetime
    add_column :patients, :discharged_by, :string
  end
end
