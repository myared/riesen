require "test_helper"

class VitalTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "John",
      last_name: "Doe",
      age: 30,
      mrn: "VT_#{SecureRandom.hex(4)}"
    )
    
    @vital = @patient.vitals.build(
      heart_rate: 72,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      respiratory_rate: 16,
      temperature: 37.0,
      spo2: 98,
      weight: 75.5,
      recorded_at: Time.current
    )
  end

  test "should be valid with valid attributes" do
    assert @vital.valid?
  end

  test "should belong to a patient" do
    @vital.patient = nil
    assert_not @vital.valid?
  end

  test "heart_rate should be greater than 0" do
    @vital.heart_rate = 0
    assert_not @vital.valid?
    @vital.heart_rate = -1
    assert_not @vital.valid?
    @vital.heart_rate = 60
    assert @vital.valid?
  end

  test "blood_pressure_systolic should be greater than 0" do
    @vital.blood_pressure_systolic = 0
    assert_not @vital.valid?
    @vital.blood_pressure_systolic = 120
    assert @vital.valid?
  end

  test "blood_pressure_diastolic should be greater than 0" do
    @vital.blood_pressure_diastolic = 0
    assert_not @vital.valid?
    @vital.blood_pressure_diastolic = 80
    assert @vital.valid?
  end

  test "respiratory_rate should be greater than 0" do
    @vital.respiratory_rate = 0
    assert_not @vital.valid?
    @vital.respiratory_rate = 16
    assert @vital.valid?
  end

  test "spo2 should be between 0 and 100" do
    @vital.spo2 = -1
    assert_not @vital.valid?
    @vital.spo2 = 101
    assert_not @vital.valid?
    @vital.spo2 = 0
    assert @vital.valid?
    @vital.spo2 = 100
    assert @vital.valid?
    @vital.spo2 = 98
    assert @vital.valid?
  end

  test "blood_pressure returns formatted string" do
    assert_equal "120/80", @vital.blood_pressure
  end

  test "blood_pressure returns nil when systolic is missing" do
    @vital.blood_pressure_systolic = nil
    assert_nil @vital.blood_pressure
  end

  test "blood_pressure returns nil when diastolic is missing" do
    @vital.blood_pressure_diastolic = nil
    assert_nil @vital.blood_pressure
  end

  test "temperature_fahrenheit converts correctly" do
    @vital.temperature = 37.0
    assert_equal 98.6, @vital.temperature_fahrenheit
    
    @vital.temperature = 38.5
    assert_equal 101.3, @vital.temperature_fahrenheit
  end

  test "temperature_fahrenheit returns nil when temperature is nil" do
    @vital.temperature = nil
    assert_nil @vital.temperature_fahrenheit
  end
end