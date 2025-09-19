class AddPendingTransferToPatients < ActiveRecord::Migration[8.0]
  def change
    # Add RP eligibility timestamp to track when timer starts
    add_column :patients, :rp_eligibility_started_at, :datetime

    # Note: We'll update the location_status enum in the model to include pending_transfer
    # The integer value 7 will be used for pending_transfer status
  end
end
