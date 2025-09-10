require "test_helper"

class PatientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 25,
      mrn: "TEST002",
      location: "ED Room",
      esi_level: 2
    )
  end

  test "should get show" do
    get patient_url(@patient)
    assert_response :success
  end

  test "show displays patient name" do
    get patient_url(@patient)
    assert_response :success
    assert_match @patient.full_name, response.body
  end

  test "show includes return path" do
    get patient_url(@patient), headers: { "HTTP_REFERER" => dashboard_triage_url }
    assert_response :success
    assert_select "a.modal-close[href=?]", dashboard_triage_url
  end

  test "show displays patient vitals" do
    @patient.vitals.create!(
      heart_rate: 72,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      recorded_at: Time.current
    )
    
    get patient_url(@patient)
    assert_response :success
    assert_match "72 bpm", response.body
    assert_match "120/80", response.body
  end

  test "show displays patient events" do
    @patient.events.create!(
      action: "Triage completed",
      performed_by: "Triage RN",
      time: Time.current
    )
    
    get patient_url(@patient)
    assert_response :success
    assert_match "Triage completed", response.body
  end
end