require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 25,
      mrn: "TEST001",
      location: "Waiting Room",
      esi_level: 3,
      wait_time_minutes: 15
    )
  end

  test "should get triage" do
    get dashboard_triage_url
    assert_response :success
    assert_select "h2", "Waiting Patients"
  end

  test "should get rp" do
    get dashboard_rp_url
    assert_response :success
    assert_select "h2", "Results Pending Patients"
  end

  test "should get ed_rn" do
    get dashboard_ed_rn_url
    assert_response :success
    assert_select "h2", "ED RN Patients"
  end

  test "should get charge_rn" do
    get dashboard_charge_rn_url
    assert_response :success
    assert_select "h2", "All Department Patients"
  end

  test "should get provider" do
    get dashboard_provider_url
    assert_response :success
    assert_select "h2", "Provider Patients"
  end

  test "triage shows waiting room patients" do
    get dashboard_triage_url
    assert_response :success
    assert_match @patient.full_name, response.body
  end

  test "dashboard loads statistics" do
    get dashboard_triage_url
    assert_response :success
    assert_select ".stat-card", minimum: 3
  end

  test "patient table displays required columns" do
    get dashboard_triage_url
    assert_response :success
    assert_select "th", "Patient"
    assert_select "th", "ESI"
    assert_select "th", "Chief Complaint"
  end

  test "root path redirects to triage dashboard" do
    get root_url
    assert_response :success
    assert_select "h2", "Waiting Patients"
  end
end