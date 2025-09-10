class CreateCarePathways < ActiveRecord::Migration[8.0]
  def change
    # Main care pathway table
    create_table :care_pathways do |t|
      t.references :patient, null: false, foreign_key: true
      t.integer :pathway_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.string :started_by
      t.string :completed_by
      t.timestamps
    end
    
    # Triage pathway steps
    create_table :care_pathway_steps do |t|
      t.references :care_pathway, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :sequence, null: false
      t.boolean :completed, default: false
      t.datetime :completed_at
      t.string :completed_by
      t.jsonb :data # Store step-specific data (symptoms, vitals, etc.)
      t.timestamps
    end
    
    # Emergency room orders (labs, meds, imaging)
    create_table :care_pathway_orders do |t|
      t.references :care_pathway, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :order_type, null: false
      t.integer :status, null: false, default: 0
      t.datetime :ordered_at
      t.string :ordered_by
      t.datetime :status_updated_at
      t.string :status_updated_by
      t.text :notes
      t.jsonb :results # Store results data when available
      t.timestamps
    end
    
    # Emergency room procedures
    create_table :care_pathway_procedures do |t|
      t.references :care_pathway, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :completed, default: false
      t.datetime :completed_at
      t.string :completed_by
      t.text :notes
      t.timestamps
    end
    
    # Clinical endpoints/goals
    create_table :care_pathway_clinical_endpoints do |t|
      t.references :care_pathway, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false
      t.boolean :achieved, default: false
      t.datetime :achieved_at
      t.string :achieved_by
      t.text :notes
      t.timestamps
    end
    
    # Add indexes for better performance
    add_index :care_pathways, :pathway_type
    add_index :care_pathways, :status
    add_index :care_pathway_steps, [:care_pathway_id, :sequence]
    add_index :care_pathway_steps, :completed
    add_index :care_pathway_orders, :order_type
    add_index :care_pathway_orders, :status
    add_index :care_pathway_procedures, :completed
    add_index :care_pathway_clinical_endpoints, :achieved
  end
end
