require "test_helper"

class PatientTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.new(
      first_name: "John",
      last_name: "Doe",
      age: 30,
      mrn: "PT_#{SecureRandom.hex(4)}",
      esi_level: 3,
      pain_score: 5,
      location: "Waiting Room",
      chief_complaint: "Headache",
      arrival_time: Time.current,
      wait_time_minutes: 10
    )
  end

  test "should be valid with valid attributes" do
    assert @patient.valid?
  end

  test "should require first name" do
    @patient.first_name = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:first_name], "can't be blank"
  end

  test "should require last name" do
    @patient.last_name = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:last_name], "can't be blank"
  end

  test "should require age" do
    @patient.age = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:age], "can't be blank"
  end

  test "age should be greater than 0" do
    @patient.age = 0
    assert_not @patient.valid?
    @patient.age = -1
    assert_not @patient.valid?
    @patient.age = 1
    assert @patient.valid?
  end

  test "should require mrn" do
    @patient.mrn = nil
    assert_not @patient.valid?
    assert_includes @patient.errors[:mrn], "can't be blank"
  end

  test "mrn should be unique" do
    @patient.save!
    duplicate_patient = @patient.dup
    assert_not duplicate_patient.valid?
    assert_includes duplicate_patient.errors[:mrn], "has already been taken"
  end

  test "esi_level should be between 1 and 5" do
    @patient.esi_level = 0
    assert_not @patient.valid?
    @patient.esi_level = 6
    assert_not @patient.valid?
    (1..5).each do |level|
      @patient.esi_level = level
      assert @patient.valid?
    end
  end

  test "pain_score should be between 1 and 10" do
    @patient.pain_score = 0
    assert_not @patient.valid?
    @patient.pain_score = 11
    assert_not @patient.valid?
    (1..10).each do |score|
      @patient.pain_score = score
      assert @patient.valid?
    end
  end

  test "full_name returns first and last name" do
    assert_equal "John Doe", @patient.full_name
  end

  test "wait_progress_percentage calculates correctly" do
    @patient.esi_level = 3
    @patient.wait_time_minutes = 15
    assert_equal 50, @patient.wait_progress_percentage

    @patient.wait_time_minutes = 30
    assert_equal 100, @patient.wait_progress_percentage

    @patient.wait_time_minutes = 45
    assert_equal 100, @patient.wait_progress_percentage
  end

  test "latest_vital returns most recent vital" do
    @patient.save!
    old_vital = @patient.vitals.create!(
      heart_rate: 70,
      recorded_at: 1.hour.ago
    )
    new_vital = @patient.vitals.create!(
      heart_rate: 80,
      recorded_at: Time.current
    )

    assert_equal new_vital, @patient.latest_vital
  end

  test "should destroy associated vitals when destroyed" do
    @patient.save!
    @patient.vitals.create!(heart_rate: 70, recorded_at: Time.current)

    assert_difference "Vital.count", -1 do
      @patient.destroy
    end
  end

  test "should destroy associated events when destroyed" do
    @patient.save!
    @patient.events.create!(
      action: "Arrived",
      performed_by: "Registration",
      time: Time.current
    )

    assert_difference "Event.count", -1 do
      @patient.destroy
    end
  end

  test "location_status enum and scopes" do
    @patient.save!

    # Test default status
    assert @patient.location_waiting_room?

    # Test enum transitions
    @patient.update!(location_status: :triage)
    assert @patient.location_triage?

    @patient.update!(location_status: :needs_room_assignment)
    assert @patient.location_needs_room_assignment?

    @patient.update!(location_status: :results_pending)
    assert @patient.location_results_pending?

    @patient.update!(location_status: :ed_room)
    assert @patient.location_ed_room?

    @patient.update!(location_status: :treatment)
    assert @patient.location_treatment?

    @patient.update!(location_status: :discharged)
    assert @patient.location_discharged?
  end

  test "scopes filter patients correctly" do
    @patient.save!

    # Create patients with different statuses
    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Patient", age: 25, mrn: "WAIT001",
      location_status: :waiting_room, esi_level: 3
    )

    triage_patient = Patient.create!(
      first_name: "Triage", last_name: "Patient", age: 30, mrn: "TRIAGE001",
      location_status: :triage, esi_level: 4
    )

    ed_patient = Patient.create!(
      first_name: "ED", last_name: "Patient", age: 35, mrn: "ED001",
      location_status: :ed_room, esi_level: 2
    )

    treatment_patient = Patient.create!(
      first_name: "Treatment", last_name: "Patient", age: 40, mrn: "TREAT001",
      location_status: :treatment, esi_level: 3
    )

    provider_patient = Patient.create!(
      first_name: "Provider", last_name: "Patient", age: 45, mrn: "PROV001",
      location_status: :ed_room, provider: "Dr. Smith", esi_level: 2
    )

    critical_patient = Patient.create!(
      first_name: "Critical", last_name: "Patient", age: 50, mrn: "CRIT001",
      location_status: :ed_room, esi_level: 1
    )

    # Test waiting scope
    waiting_patients = Patient.waiting
    assert_includes waiting_patients, waiting_patient
    assert_not_includes waiting_patients, triage_patient
    assert_not_includes waiting_patients, ed_patient

    # Test in_triage scope
    in_triage_patients = Patient.in_triage
    assert_includes in_triage_patients, waiting_patient
    assert_includes in_triage_patients, triage_patient
    assert_not_includes in_triage_patients, ed_patient

    # Test in_ed scope
    in_ed_patients = Patient.in_ed
    assert_includes in_ed_patients, ed_patient
    assert_includes in_ed_patients, treatment_patient
    assert_includes in_ed_patients, provider_patient
    assert_includes in_ed_patients, critical_patient
    assert_not_includes in_ed_patients, waiting_patient

    # Test with_provider scope
    with_provider_patients = Patient.with_provider
    assert_includes with_provider_patients, provider_patient
    assert_not_includes with_provider_patients, ed_patient

    # Test critical scope (ESI 1 and 2)
    critical_patients = Patient.critical
    assert_includes critical_patients, critical_patient
    assert_includes critical_patients, ed_patient  # ESI 2 is also critical
    assert_includes critical_patients, provider_patient  # ESI 2 is also critical
    assert_not_includes critical_patients, waiting_patient  # ESI 3 is not critical
  end

  test "esi_target_minutes returns correct targets" do
    assert_equal 0, Patient.new(esi_level: 1).esi_target_minutes
    assert_equal 10, Patient.new(esi_level: 2).esi_target_minutes
    assert_equal 30, Patient.new(esi_level: 3).esi_target_minutes
    assert_equal 60, Patient.new(esi_level: 4).esi_target_minutes
    assert_equal 120, Patient.new(esi_level: 5).esi_target_minutes
    assert_equal 30, Patient.new(esi_level: nil).esi_target_minutes # default
  end

  test "esi_target_label returns correct labels" do
    assert_equal "Immediate", Patient.new(esi_level: 1).esi_target_label
    assert_equal "10m target", Patient.new(esi_level: 2).esi_target_label
    assert_equal "30m target", Patient.new(esi_level: 3).esi_target_label
    assert_equal "60m target", Patient.new(esi_level: 4).esi_target_label
    assert_equal "120m target", Patient.new(esi_level: 5).esi_target_label
  end

  test "esi_description returns correct descriptions" do
    assert_equal "Resuscitation", Patient.new(esi_level: 1).esi_description
    assert_equal "Emergent", Patient.new(esi_level: 2).esi_description
    assert_equal "Urgent", Patient.new(esi_level: 3).esi_description
    assert_equal "Less Urgent", Patient.new(esi_level: 4).esi_description
    assert_equal "Non-Urgent", Patient.new(esi_level: 5).esi_description
  end

  test "overdue? returns correct status" do
    # Patient not overdue
    patient = Patient.new(esi_level: 3, wait_time_minutes: 20)
    assert_not patient.overdue?

    # Patient overdue
    patient.wait_time_minutes = 45
    assert patient.overdue?

    # Critical patient should be overdue immediately
    patient = Patient.new(esi_level: 1, wait_time_minutes: 1)
    assert patient.overdue?
  end

  test "critical? returns correct status" do
    assert Patient.new(esi_level: 1).critical?
    assert Patient.new(esi_level: 2).critical?
    assert_not Patient.new(esi_level: 3).critical?
    assert_not Patient.new(esi_level: 4).critical?
    assert_not Patient.new(esi_level: 5).critical?
  end

  test "room assignment workflow" do
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: false)
    room_number = "ED_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :ed, status: :available)

    # Assign room via Room model
    room.assign_patient(@patient)
    @patient.reload

    # Check patient status updated correctly
    assert @patient.location_ed_room?
    assert_equal room_number, @patient.room_number
  end

  test "rp eligible patient workflow" do
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: true)
    room_number = "RP_#{SecureRandom.hex(4)}"
    room = Room.create!(number: room_number, room_type: :rp, status: :available)

    # Assign room via Room model
    room.assign_patient(@patient)
    @patient.reload

    # Check patient status updated correctly for RP
    assert @patient.location_results_pending?
    assert_equal room_number, @patient.room_number
  end

  test "patient transitions through complete workflow" do
    @patient.save!

    # Start in waiting room
    assert @patient.location_waiting_room?

    # Move to triage
    @patient.update!(location_status: :triage)
    assert @patient.location_triage?

    # Complete triage, needs room assignment
    @patient.update!(location_status: :needs_room_assignment, rp_eligible: false)
    assert @patient.location_needs_room_assignment?

    # Assign to ED room
    @patient.update!(location_status: :ed_room, room_number: "ED01")
    assert @patient.location_ed_room?
    assert_equal "ED01", @patient.room_number

    # Move to treatment
    @patient.update!(location_status: :treatment)
    assert @patient.location_treatment?

    # Discharge
    @patient.update!(location_status: :discharged, room_number: nil)
    assert @patient.location_discharged?
    assert_nil @patient.room_number
  end

  test "rp_eligible boolean field works correctly" do
    @patient.save!

    # Test nil value (should be falsy)
    assert_not @patient.rp_eligible

    # Test false value
    @patient.update!(rp_eligible: false)
    assert_not @patient.rp_eligible

    # Test true value
    @patient.update!(rp_eligible: true)
    assert @patient.rp_eligible
  end

  test "patient can have multiple vitals over time" do
    @patient.save!

    # Create initial vitals
    vital1 = @patient.vitals.create!(
      heart_rate: 72,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      recorded_at: 2.hours.ago
    )

    # Create updated vitals
    vital2 = @patient.vitals.create!(
      heart_rate: 85,
      blood_pressure_systolic: 130,
      blood_pressure_diastolic: 85,
      recorded_at: 1.hour.ago
    )

    # Latest vital should be the most recent
    assert_equal vital2, @patient.latest_vital
    assert_equal 2, @patient.vitals.count
  end

  test "patient can have multiple events" do
    @patient.save!

    # Create arrival event
    event1 = @patient.events.create!(
      action: "Arrival",
      details: "Patient arrived via ambulance",
      performed_by: "Registration",
      time: 2.hours.ago,
      category: "administrative"
    )

    # Create triage event
    event2 = @patient.events.create!(
      action: "Triage completed",
      details: "ESI 3 assigned",
      performed_by: "Triage RN",
      time: 1.hour.ago,
      category: "clinical"
    )

    assert_equal 2, @patient.events.count
    assert_includes @patient.events, event1
    assert_includes @patient.events, event2
  end

  test "wait_progress_percentage handles edge cases" do
    # ESI 1 (immediate) should show 100% immediately
    patient = Patient.new(esi_level: 1, wait_time_minutes: 0)
    assert_equal 100, patient.wait_progress_percentage

    # Very long wait should cap at 100%
    patient = Patient.new(esi_level: 3, wait_time_minutes: 1000)
    assert_equal 100, patient.wait_progress_percentage

    # Zero wait time
    patient = Patient.new(esi_level: 3, wait_time_minutes: 0)
    assert_equal 0, patient.wait_progress_percentage
  end

  test "patient associations work correctly" do
    @patient.save!

    # Test care pathways association
    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :not_started
    )

    assert_includes @patient.care_pathways, pathway

    # Test active care pathway
    pathway.update!(status: :in_progress)
    @patient.reload # Reload to ensure association is fresh
    assert_equal pathway, @patient.active_care_pathway

    # Test completed pathway doesn't show as active
    pathway.update!(status: :completed)
    @patient.reload # Reload to ensure association is fresh
    assert_nil @patient.active_care_pathway
  end
end
