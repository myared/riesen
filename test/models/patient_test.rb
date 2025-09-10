require "test_helper"

class PatientTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.new(
      first_name: "John",
      last_name: "Doe",
      age: 30,
      mrn: "1234",
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
end