class AddRoomAssignmentNeededAtToPatients < ActiveRecord::Migration[8.0]
  def change
    add_column :patients, :room_assignment_needed_at, :datetime
  end
end
