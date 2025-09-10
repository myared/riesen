class AddRoomNumberToPatients < ActiveRecord::Migration[8.0]
  def change
    add_column :patients, :room_number, :string
    add_column :patients, :triage_completed_at, :datetime
  end
end
