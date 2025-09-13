class AddMedicationAndImagingFieldsToCarePathwayOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :care_pathway_orders, :administered_at, :datetime
    add_column :care_pathway_orders, :exam_started_at, :datetime
    add_column :care_pathway_orders, :exam_completed_at, :datetime
  end
end
