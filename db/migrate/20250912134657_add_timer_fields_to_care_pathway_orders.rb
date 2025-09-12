class AddTimerFieldsToCarePathwayOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :care_pathway_orders, :collected_at, :datetime
    add_column :care_pathway_orders, :in_lab_at, :datetime
    add_column :care_pathway_orders, :resulted_at, :datetime
    
    # Track timer status for each transition
    add_column :care_pathway_orders, :timer_status, :string, default: 'green'
    add_column :care_pathway_orders, :last_status_duration_minutes, :integer
    
    add_index :care_pathway_orders, :timer_status
  end
end