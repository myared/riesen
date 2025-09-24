class AddStartingFieldsToCarePathwayClinicalEndpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :care_pathway_clinical_endpoints, :started, :boolean, default: false
    add_column :care_pathway_clinical_endpoints, :started_at, :datetime
    add_column :care_pathway_clinical_endpoints, :started_by, :string
  end
end
