class AddAssignedToCarePathwayOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :care_pathway_orders, :assigned_to, :string
  end
end
