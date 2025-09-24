class AddOrderingFieldsToCarePathwayProcedures < ActiveRecord::Migration[8.0]
  def change
    add_column :care_pathway_procedures, :ordered, :boolean, default: false
    add_column :care_pathway_procedures, :ordered_at, :datetime
    add_column :care_pathway_procedures, :ordered_by, :string
  end
end
