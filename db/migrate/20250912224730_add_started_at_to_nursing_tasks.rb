class AddStartedAtToNursingTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :nursing_tasks, :started_at, :datetime
    
    # Migrate existing pending tasks to have started_at based on created_at
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE nursing_tasks 
          SET started_at = created_at 
          WHERE status = 0 AND started_at IS NULL
        SQL
      end
    end
  end
end
