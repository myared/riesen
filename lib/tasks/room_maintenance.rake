namespace :rooms do
  desc "Clean up room assignments for discharged patients"
  task cleanup: :environment do
    puts "Reconciling room assignments..."
    Room.reconcile_assignments!

    dangling = Patient.where(location_status: :discharged).where.not(room_number: nil)
    released = dangling.update_all(room_number: nil)

    puts "Cleared room numbers for #{released} discharged patients" if released.positive?
    puts "Room cleanup complete."
  end
end
