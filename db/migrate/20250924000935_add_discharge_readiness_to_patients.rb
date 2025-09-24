class AddDischargeReadinessToPatients < ActiveRecord::Migration[8.0]
  def change
    add_column :patients, :ready_for_checkout, :boolean, default: false
    add_column :patients, :ready_for_checkout_at, :datetime
  end
end
