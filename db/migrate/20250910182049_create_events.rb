class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :patient, null: false, foreign_key: true
      t.datetime :time
      t.string :action
      t.text :details
      t.string :performed_by
      t.string :category

      t.timestamps
    end
  end
end
