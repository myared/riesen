class CreateRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :rooms do |t|
      t.string :number, null: false
      t.integer :room_type, null: false, default: 0
      t.integer :status, default: 0
      t.references :current_patient, foreign_key: { to_table: :patients }, null: true
      t.integer :esi_level
      t.integer :time_in_room

      t.timestamps
    end
    
    add_index :rooms, :number, unique: true
    add_index :rooms, :room_type
    add_index :rooms, :status
  end
end
