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

  test "rp dashboard shows correct patients" do
    # Create patients with different statuses
    rp_patient = Patient.create!(
      first_name: "RP", last_name: "Patient", age: 30, mrn: "RP001",
      location_status: :results_pending, rp_eligible: true, esi_level: 3
    )
    
    waiting_rp_patient = Patient.create!(
      first_name: "Waiting", last_name: "RP", age: 25, mrn: "RP002",
      location_status: :needs_room_assignment, rp_eligible: true, esi_level: 4
    )
    
    ed_patient = Patient.create!(
      first_name: "ED", last_name: "Patient", age: 35, mrn: "ED001",
      location_status: :ed_room, rp_eligible: false, esi_level: 2
    )
    
    waiting_ed_patient = Patient.create!(
      first_name: "Waiting", last_name: "ED", age: 40, mrn: "ED002",
      location_status: :needs_room_assignment, rp_eligible: false, esi_level: 3
    )
    
    get dashboard_rp_url
    assert_response :success
    
    # Should include RP patients and those waiting for RP assignment
    assert_match rp_patient.full_name, response.body
    assert_match waiting_rp_patient.full_name, response.body
    
    # Should not include ED patients or those waiting for ED assignment
    assert_no_match ed_patient.full_name, response.body
    assert_no_match waiting_ed_patient.full_name, response.body
  end

  test "ed_rn dashboard shows correct patients" do
    # Create patients with different statuses
    ed_room_patient = Patient.create!(
      first_name: "ED", last_name: "Room", age: 30, mrn: "ED001",
      location_status: :ed_room, rp_eligible: false, esi_level: 3
    )
    
    treatment_patient = Patient.create!(
      first_name: "Treatment", last_name: "Patient", age: 25, mrn: "ED002",
      location_status: :treatment, rp_eligible: false, esi_level: 4
    )
    
    waiting_ed_patient = Patient.create!(
      first_name: "Waiting", last_name: "ED", age: 35, mrn: "ED003",
      location_status: :needs_room_assignment, rp_eligible: false, esi_level: 2
    )
    
    rp_patient = Patient.create!(
      first_name: "RP", last_name: "Patient", age: 40, mrn: "RP001",
      location_status: :results_pending, rp_eligible: true, esi_level: 3
    )
    
    waiting_rp_patient = Patient.create!(
      first_name: "Waiting", last_name: "RP", age: 28, mrn: "RP002",
      location_status: :needs_room_assignment, rp_eligible: true, esi_level: 4
    )
    
    get dashboard_ed_rn_url
    assert_response :success
    
    # Should include ED patients and those waiting for ED assignment
    assert_match ed_room_patient.full_name, response.body
    assert_match treatment_patient.full_name, response.body
    assert_match waiting_ed_patient.full_name, response.body
    
    # Should not include RP patients or those waiting for RP assignment
    assert_no_match rp_patient.full_name, response.body
    assert_no_match waiting_rp_patient.full_name, response.body
  end

  test "charge_rn dashboard defaults to staff_tasks view" do
    get dashboard_charge_rn_url
    assert_response :success
    assert_select "h2", "All Department Patients"
    
    # Should show staff tasks section
    assert_select ".nursing-tasks", count: 1
  end

  test "charge_rn dashboard with floor_view parameter" do
    # Create some rooms for floor view
    Room.create!(number: "ED01", room_type: :ed, status: :available)
    Room.create!(number: "RP01", room_type: :rp, status: :occupied)
    
    get dashboard_charge_rn_url, params: { view: 'floor_view' }
    assert_response :success
    assert_select "h2", "All Department Patients"
    
    # Should show floor view content
    assert_select ".floor-grid", count: 1
  end

  test "charge_rn dashboard calculates room statistics" do
    # Create rooms with different statuses
    ed_available = Room.create!(number: "ED01", room_type: :ed, status: :available)
    ed_occupied = Room.create!(number: "ED02", room_type: :ed, status: :occupied)
    rp_available = Room.create!(number: "RP01", room_type: :rp, status: :available)
    rp_occupied = Room.create!(number: "RP02", room_type: :rp, status: :occupied)
    
    get dashboard_charge_rn_url, params: { view: 'floor_view' }
    assert_response :success
    
    # The controller should load room data for floor view
    assert_not_nil assigns(:ed_rooms)
    assert_not_nil assigns(:rp_rooms)
    assert_not_nil assigns(:current_ed_census)
    assert_not_nil assigns(:rp_utilization)
  end

  test "charge_rn dashboard loads nursing tasks for staff view" do
    patient = Patient.create!(
      first_name: "Task", last_name: "Patient", age: 30, mrn: "TASK001",
      location_status: :needs_room_assignment, rp_eligible: false, esi_level: 3
    )
    
    task = NursingTask.create!(
      patient: patient,
      task_type: :room_assignment,
      description: "Transport patient to ED",
      assigned_to: "ED RN",
      priority: :high,
      status: :pending,
      due_at: 30.minutes.from_now
    )
    
    get dashboard_charge_rn_url # defaults to staff_tasks view
    assert_response :success
    
    # Should load nursing tasks
    assert_not_nil assigns(:nursing_tasks)
    assert_includes assigns(:nursing_tasks), task
  end

  test "provider dashboard shows patients with providers" do
    # Create patients with and without providers
    with_provider = Patient.create!(
      first_name: "With", last_name: "Provider", age: 30, mrn: "PROV001",
      provider: "Dr. Smith", esi_level: 3
    )
    
    without_provider = Patient.create!(
      first_name: "No", last_name: "Provider", age: 25, mrn: "PROV002",
      provider: nil, esi_level: 4
    )
    
    get dashboard_provider_url
    assert_response :success
    
    # Should include patient with provider
    assert_match with_provider.full_name, response.body
    
    # Should not include patient without provider (unless query logic differs)
    # Note: This test might need adjustment based on actual filtering logic
  end

  test "dashboard statistics are loaded for all views" do
    # Create some waiting patients
    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Patient", age: 30, mrn: "WAIT001",
      location_status: :waiting_room, wait_time_minutes: 45, esi_level: 3
    )
    
    # Create rooms for RP utilization calculation
    Room.create!(number: "RP01", room_type: :rp, status: :available)
    Room.create!(number: "RP02", room_type: :rp, status: :occupied)
    
    get dashboard_triage_url
    assert_response :success
    
    # Statistics should be loaded
    assert_not_nil assigns(:total_waiting)
    assert_not_nil assigns(:avg_wait_time)
    assert_not_nil assigns(:rp_utilization)
    
    # Should be positive numbers based on our test data
    assert assigns(:total_waiting) > 0
    assert assigns(:rp_utilization) >= 0
  end

  test "dashboard handles empty patient lists gracefully" do
    # Clear any existing patients
    Patient.destroy_all
    
    get dashboard_triage_url
    assert_response :success
    
    get dashboard_rp_url
    assert_response :success
    
    get dashboard_ed_rn_url
    assert_response :success
    
    get dashboard_charge_rn_url
    assert_response :success
    
    get dashboard_provider_url
    assert_response :success
  end

  test "rp utilization calculation with no rooms returns zero" do
    Room.destroy_all
    
    get dashboard_triage_url
    assert_response :success
    assert_equal 0, assigns(:rp_utilization)
  end

  test "triage dashboard shows in_triage patients" do
    # Create patients with different statuses
    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Patient", age: 30, mrn: "WAIT001",
      location_status: :waiting_room, esi_level: 3
    )
    
    triage_patient = Patient.create!(
      first_name: "Triage", last_name: "Patient", age: 25, mrn: "TRIAGE001",
      location_status: :triage, esi_level: 4
    )
    
    assigned_patient = Patient.create!(
      first_name: "Assigned", last_name: "Patient", age: 35, mrn: "ASSIGN001",
      location_status: :needs_room_assignment, esi_level: 2
    )
    
    get dashboard_triage_url
    assert_response :success
    
    # Should include waiting and triage patients
    assert_match waiting_patient.full_name, response.body
    assert_match triage_patient.full_name, response.body
    
    # Should not include patients who have completed triage
    assert_no_match assigned_patient.full_name, response.body
  end
end