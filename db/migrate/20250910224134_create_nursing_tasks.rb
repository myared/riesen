class CreateNursingTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :nursing_tasks do |t|
      t.references :patient, null: false, foreign_key: true
      t.integer :task_type, null: false
      t.string :description, null: false
      t.string :assigned_to
      t.integer :priority, default: 1
      t.integer :status, default: 0
      t.datetime :due_at
      t.datetime :completed_at
      t.string :room_number

      t.timestamps
    end
    
    add_index :nursing_tasks, :status
    add_index :nursing_tasks, :assigned_to
    add_index :nursing_tasks, :priority
  end
end
