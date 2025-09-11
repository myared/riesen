require "test_helper"

class RoomTest < ActiveSupport::TestCase
  setup do
    @ed_room = Room.create!(
      number: "RT_ED_#{SecureRandom.hex(4)}",
      room_type: :ed,
      status: :available
    )
    
    @rp_room = Room.create!(
      number: "RT_RP_#{SecureRandom.hex(4)}", 
      room_type: :rp,
      status: :available
    )
    
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 30,
      mrn: "RT_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      rp_eligible: false
    )
    
    @rp_eligible_patient = Patient.create!(
      first_name: "RP",
      last_name: "Patient", 
      age: 25,
      mrn: "RT_#{SecureRandom.hex(4)}",
      esi_level: 4,
      location_status: :needs_room_assignment,
      rp_eligible: true
    )
  end

  test "room validations" do
    room = Room.new
    assert_not room.valid?
    assert_includes room.errors[:number], "can't be blank"
    
    # Test that a room with number and room_type is valid
    room.number = "TEST123"
    room.room_type = :ed
    assert room.valid?
  end

  test "room number uniqueness" do
    duplicate_room = Room.new(number: @ed_room.number, room_type: :ed)
    assert_not duplicate_room.valid?
    assert_includes duplicate_room.errors[:number], "has already been taken"
  end

  test "room type enum" do
    assert @ed_room.room_type_ed?
    assert @rp_room.room_type_rp?
    assert_not @ed_room.room_type_rp?
    assert_not @rp_room.room_type_ed?
  end

  test "room status enum" do
    assert @ed_room.status_available?
    
    @ed_room.update!(status: :occupied)
    assert @ed_room.status_occupied?
    
    @ed_room.update!(status: :cleaning)
    assert @ed_room.status_cleaning?
    
    @ed_room.update!(status: :maintenance)
    assert @ed_room.status_maintenance?
  end

  test "scopes work correctly" do
    occupied_room = Room.create!(number: "RT_#{SecureRandom.hex(4)}", room_type: :ed, status: :occupied)
    
    assert_includes Room.ed_rooms, @ed_room
    assert_includes Room.ed_rooms, occupied_room
    assert_not_includes Room.ed_rooms, @rp_room
    
    assert_includes Room.rp_rooms, @rp_room
    assert_not_includes Room.rp_rooms, @ed_room
    
    assert_includes Room.available_rooms, @ed_room
    assert_includes Room.available_rooms, @rp_room
    assert_not_includes Room.available_rooms, occupied_room
    
    assert_includes Room.occupied_rooms, occupied_room
    assert_not_includes Room.occupied_rooms, @ed_room
  end

  test "assign_patient updates room and patient correctly for ED room" do
    assert_difference('Event.count') do
      @ed_room.assign_patient(@patient)
    end
    
    @ed_room.reload
    @patient.reload
    
    # Check room updates
    assert_equal @patient, @ed_room.current_patient
    assert @ed_room.status_occupied?
    assert_equal 0, @ed_room.time_in_room
    assert_equal @patient.esi_level, @ed_room.esi_level
    
    # Check patient updates
    assert @patient.location_ed_room?
    assert_equal @ed_room.number, @patient.room_number
    
    # Check event creation
    event = Event.last
    assert_equal @patient, event.patient
    assert_equal "Assigned to #{@ed_room.number}", event.action
    assert_includes event.details, "ED room"
    assert_equal "ED RN", event.performed_by
  end

  test "assign_patient updates room and patient correctly for RP room" do
    assert_difference('Event.count') do
      @rp_room.assign_patient(@rp_eligible_patient)
    end
    
    @rp_room.reload
    @rp_eligible_patient.reload
    
    # Check room updates
    assert_equal @rp_eligible_patient, @rp_room.current_patient
    assert @rp_room.status_occupied?
    assert_equal 0, @rp_room.time_in_room
    assert_equal @rp_eligible_patient.esi_level, @rp_room.esi_level
    
    # Check patient updates
    assert @rp_eligible_patient.location_results_pending?
    assert_equal @rp_room.number, @rp_eligible_patient.room_number
    
    # Check event creation
    event = Event.last
    assert_equal @rp_eligible_patient, event.patient
    assert_equal "Assigned to #{@rp_room.number}", event.action
    assert_includes event.details, "RP room"
    assert_equal "RP RN", event.performed_by
  end

  test "assign_patient is transactional" do
    # Test transaction behavior by forcing a database error
    original_number = @ed_room.number
    
    # Create a conflicting room to trigger a uniqueness error
    conflict_room_number = "CONFLICT_#{SecureRandom.hex(4)}"
    Room.create!(number: conflict_room_number, room_type: :ed, status: :available)
    
    # Monkey patch the update! method to cause an error mid-transaction
    @ed_room.define_singleton_method(:update!) do |attrs|
      super(attrs.merge(number: conflict_room_number))  # This will cause a uniqueness error
    end
    
    assert_raises(ActiveRecord::RecordInvalid) do
      @ed_room.assign_patient(@patient)
    end
    
    @ed_room.reload
    @patient.reload
    
    # Verify no changes were made due to transaction rollback
    assert_nil @ed_room.current_patient
    assert @ed_room.status_available?
    assert @patient.location_needs_room_assignment?
    assert_nil @patient.room_number
  end

  test "release room clears patient assignment" do
    @ed_room.assign_patient(@patient)
    
    @ed_room.release
    @ed_room.reload
    @patient.reload
    
    # Check room is cleared
    assert_nil @ed_room.current_patient
    assert @ed_room.status_cleaning?
    assert_nil @ed_room.esi_level
    assert_nil @ed_room.time_in_room
    
    # Check patient room is cleared
    assert_nil @patient.room_number
  end

  test "release room without patient" do
    assert_nothing_raised do
      @ed_room.release
    end
    
    @ed_room.reload
    assert_nil @ed_room.current_patient
    assert @ed_room.status_cleaning?
  end

  test "mark_available updates status" do
    @ed_room.update!(status: :cleaning)
    @ed_room.mark_available
    
    assert @ed_room.status_available?
  end

  test "display_label formats correctly" do
    # The display_label method removes uppercase letters and prepends room type
    # Since we're using random hex strings, test the format instead of exact values
    assert_match /^ED/, @ed_room.display_label
    assert_match /^RP/, @rp_room.display_label
    
    # Test with a simple room number
    simple_room = Room.create!(number: "12", room_type: :ed, status: :available)
    assert_equal "ED12", simple_room.display_label
  end

  test "can_accept_patient for ED room" do
    # ED room can accept any patient
    assert @ed_room.can_accept_patient?(@patient)
    assert @ed_room.can_accept_patient?(@rp_eligible_patient)
    
    # But not if room is not available
    @ed_room.update!(status: :occupied)
    assert_not @ed_room.can_accept_patient?(@patient)
  end

  test "can_accept_patient for RP room" do
    # RP room can only accept RP eligible patients
    assert @rp_room.can_accept_patient?(@rp_eligible_patient)
    assert_not @rp_room.can_accept_patient?(@patient)
    
    # But not if room is not available
    @rp_room.update!(status: :occupied)
    assert_not @rp_room.can_accept_patient?(@rp_eligible_patient)
  end

  test "assign_patient works with room status transitions" do
    # Test cleaning -> occupied via assign_patient
    @ed_room.update!(status: :cleaning)
    @ed_room.assign_patient(@patient)
    
    assert @ed_room.status_occupied?
  end
end
