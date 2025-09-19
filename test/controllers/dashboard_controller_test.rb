require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 25,
      mrn: "DCT_#{SecureRandom.hex(4)}",
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
    get dashboard_charge_rn_url(view: 'floor_view')
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
    assert_select "th", "Care Pathway"
    assert_select "th", "Wait Progress"
    assert_select "th", "RP Eligible"
  end

  test "root path redirects to triage dashboard" do
    get root_url
    assert_redirected_to dashboard_triage_url
    follow_redirect!
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
    assert_select "h2", "Nursing Task Priorities"
    
    # Should show staff tasks section
    assert_select ".staff-tasks", count: 1
  end

  test "charge_rn dashboard with floor_view parameter" do
    # Create some rooms for floor view
    Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :available)
    Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :occupied)
    
    get dashboard_charge_rn_url, params: { view: 'floor_view' }
    assert_response :success
    assert_select "h2", "All Department Patients"
    
    # Should show floor view content
    assert_select ".floor-view", count: 1
  end

  test "charge_rn dashboard calculates room statistics" do
    # Create rooms with different statuses
    ed_available = Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :available)
    ed_occupied = Room.create!(number: "ED_#{SecureRandom.hex(4)}", room_type: :ed, status: :occupied)
    rp_available = Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :available)
    rp_occupied = Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :occupied)
    
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

  test "provider dashboard shows patients in results pending or ED treatment" do
    # Create patients with appropriate location statuses
    rp_patient = Patient.create!(
      first_name: "Results", last_name: "Pending", age: 30, mrn: "PROV001",
      location_status: :results_pending, esi_level: 3
    )

    ed_patient = Patient.create!(
      first_name: "ED", last_name: "Treatment", age: 25, mrn: "PROV002",
      location_status: :ed_room, esi_level: 4
    )

    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Room", age: 35, mrn: "PROV003",
      location_status: :waiting_room, esi_level: 2
    )

    get dashboard_provider_url
    assert_response :success

    # Should include patients in RP and ED treatment
    assert_match rp_patient.full_name, response.body
    assert_match ed_patient.full_name, response.body

    # Should not include patient in waiting room
    assert_no_match waiting_patient.full_name, response.body
  end

  test "dashboard statistics are loaded for all views" do
    # Create some waiting patients
    waiting_patient = Patient.create!(
      first_name: "Waiting", last_name: "Patient", age: 30, mrn: "WAIT001",
      location_status: :waiting_room, wait_time_minutes: 45, esi_level: 3
    )
    
    # Create rooms for RP utilization calculation
    Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :available)
    Room.create!(number: "RP_#{SecureRandom.hex(4)}", room_type: :rp, status: :occupied)
    
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

  # Tests for medication timers functionality (load_medication_timers method)
  test "charge_rn dashboard loads medication timers for staff view" do
    # Create a patient with care pathway and medication orders
    patient = Patient.create!(
      first_name: "Med", last_name: "Patient", age: 35, mrn: "MED001",
      location_status: :ed_room, room_number: "ED-12", esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 2.hours.ago,
      started_by: "Test RN"
    )

    # Create medication orders in different states
    ordered_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      status_updated_at: 30.minutes.ago
    )

    administered_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Ibuprofen 400mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: 1.hour.ago,
      administered_at: 30.minutes.ago
    )

    # Create non-medication order (should be excluded)
    lab_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: 45.minutes.ago
    )

    get dashboard_charge_rn_url # defaults to staff_tasks view
    assert_response :success

    # Should load medication timers
    assert_not_nil assigns(:medication_timers)

    # Should include ordered medication but not administered or lab orders
    medication_timers = assigns(:medication_timers)
    assert_equal 1, medication_timers.length

    timer = medication_timers.first
    assert_equal patient.full_name, timer[:patient_name]
    assert_equal "ED-12", timer[:room]
    assert_equal "Acetaminophen 650mg PO", timer[:medication_name]
    assert_equal "Ordered", timer[:current_status]
    assert_equal ordered_med.id, timer[:order_id]
    assert_equal patient.id, timer[:patient_id]
    assert_equal care_pathway.id, timer[:care_pathway_id]
  end

  test "load_medication_timers calculates correct timer status based on elapsed time" do
    patient = Patient.create!(
      first_name: "Timer", last_name: "Patient", age: 40, mrn: "TIMER001",
      location_status: :ed_room, room_number: "ED-15", esi_level: 2
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 2.hours.ago,
      started_by: "Test RN"
    )

    freeze_time do
      # Green timer (3 minutes elapsed)
      green_med = CarePathwayOrder.create!(
        care_pathway: care_pathway,
        name: "Morphine 2mg IV",
        order_type: :medication,
        status: :ordered,
        ordered_at: 10.minutes.ago,
        status_updated_at: 3.minutes.ago
      )

      # Yellow timer (7 minutes elapsed)
      yellow_med = CarePathwayOrder.create!(
        care_pathway: care_pathway,
        name: "Lorazepam 1mg IV",
        order_type: :medication,
        status: :ordered,
        ordered_at: 15.minutes.ago,
        status_updated_at: 7.minutes.ago
      )

      # Red timer (15 minutes elapsed)
      red_med = CarePathwayOrder.create!(
        care_pathway: care_pathway,
        name: "Zofran 4mg IV",
        order_type: :medication,
        status: :ordered,
        ordered_at: 20.minutes.ago,
        status_updated_at: 15.minutes.ago
      )

      get dashboard_charge_rn_url
      assert_response :success

      medication_timers = assigns(:medication_timers)
      assert_equal 3, medication_timers.length

      # Find timers by medication name
      green_timer = medication_timers.find { |t| t[:medication_name] == "Morphine 2mg IV" }
      yellow_timer = medication_timers.find { |t| t[:medication_name] == "Lorazepam 1mg IV" }
      red_timer = medication_timers.find { |t| t[:medication_name] == "Zofran 4mg IV" }

      # Verify timer statuses
      assert_equal 'timer-green', green_timer[:status_class]
      assert_equal 3, green_timer[:elapsed_time]

      assert_equal 'timer-yellow', yellow_timer[:status_class]
      assert_equal 7, yellow_timer[:elapsed_time]

      assert_equal 'timer-red', red_timer[:status_class]
      assert_equal 15, red_timer[:elapsed_time]
    end
  end

  test "load_medication_timers handles missing status_updated_at timestamp" do
    patient = Patient.create!(
      first_name: "Missing", last_name: "Timestamp", age: 28, mrn: "MISS001",
      location_status: :ed_room, room_number: "ED-8", esi_level: 4
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 1.hour.ago,
      started_by: "Test RN"
    )

    # Create medication order without status_updated_at
    med_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      status_updated_at: nil
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)
    assert_equal 1, medication_timers.length

    timer = medication_timers.first
    assert_equal 30, timer[:elapsed_time]  # Should use ordered_at when status_updated_at is nil
  end

  test "load_medication_timers handles patient without room assignment" do
    patient = Patient.create!(
      first_name: "No", last_name: "Room", age: 32, mrn: "NOROOM001",
      location_status: :needs_room_assignment, room_number: nil, esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 1.hour.ago,
      started_by: "Test RN"
    )

    med_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Normal Saline 1L IV",
      order_type: :medication,
      status: :ordered,
      ordered_at: 20.minutes.ago,
      status_updated_at: 20.minutes.ago
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)
    assert_equal 1, medication_timers.length

    timer = medication_timers.first
    assert_equal 'Unassigned', timer[:room]
  end

  test "load_medication_timers formats ordered_at time correctly" do
    patient = Patient.create!(
      first_name: "Time", last_name: "Format", age: 29, mrn: "TIME001",
      location_status: :ed_room, room_number: "ED-3", esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 2.hours.ago,
      started_by: "Test RN"
    )

    # Create medication order with specific time
    ordered_time = 30.minutes.ago

    med_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Epinephrine 0.3mg IM",
      order_type: :medication,
      status: :ordered,
      ordered_at: ordered_time,
      status_updated_at: ordered_time
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)
    timer = medication_timers.first

    # Should format the time using strftime("%l:%M %p PST") format
    expected_time = ordered_time.in_time_zone.strftime("%l:%M %p PST")
    assert_equal expected_time, timer[:ordered_at]
  end

  test "load_medication_timers handles nil ordered_at timestamp" do
    patient = Patient.create!(
      first_name: "Nil", last_name: "Ordered", age: 33, mrn: "NILORD001",
      location_status: :ed_room, room_number: "ED-7", esi_level: 2
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 1.hour.ago,
      started_by: "Test RN"
    )

    med_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Heparin 5000 units SC",
      order_type: :medication,
      status: :ordered,
      ordered_at: nil,
      status_updated_at: 10.minutes.ago
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)
    timer = medication_timers.first

    # Should handle nil gracefully
    assert_nil timer[:ordered_at]
  end

  test "load_medication_timers excludes administered medications" do
    patient = Patient.create!(
      first_name: "Administered", last_name: "Patient", age: 27, mrn: "ADMIN001",
      location_status: :ed_room, room_number: "ED-5", esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 2.hours.ago,
      started_by: "Test RN"
    )

    # Create both ordered and administered medications
    ordered_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Reglan",
      order_type: :medication,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      status_updated_at: 30.minutes.ago
    )

    administered_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Prednisone 40mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: 45.minutes.ago,
      administered_at: 10.minutes.ago
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)

    # Should only include ordered medication
    assert_equal 1, medication_timers.length
    timer = medication_timers.first
    assert_equal "Reglan", timer[:medication_name]
  end

  test "load_medication_timers orders by ordered_at timestamp" do
    patient = Patient.create!(
      first_name: "Order", last_name: "Test", age: 41, mrn: "ORDER001",
      location_status: :ed_room, room_number: "ED-1", esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 2.hours.ago,
      started_by: "Test RN"
    )

    # Create medications with different ordered_at times
    later_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Later Med",
      order_type: :medication,
      status: :ordered,
      ordered_at: 10.minutes.ago,
      status_updated_at: 10.minutes.ago
    )

    earlier_med = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Earlier Med",
      order_type: :medication,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      status_updated_at: 30.minutes.ago
    )

    get dashboard_charge_rn_url
    assert_response :success

    medication_timers = assigns(:medication_timers)
    assert_equal 2, medication_timers.length

    # Should be ordered by ordered_at (earliest first)
    assert_equal "Earlier Med", medication_timers.first[:medication_name]
    assert_equal "Later Med", medication_timers.second[:medication_name]
  end

  test "medication timers are not loaded for floor_view" do
    # Create a medication order
    patient = Patient.create!(
      first_name: "Floor", last_name: "View", age: 30, mrn: "FLOOR001",
      location_status: :ed_room, room_number: "ED-10", esi_level: 3
    )

    care_pathway = patient.care_pathways.create!(
      pathway_type: :triage,
      status: :completed,
      started_at: 1.hour.ago,
      started_by: "Test RN"
    )

    med_order = CarePathwayOrder.create!(
      care_pathway: care_pathway,
      name: "Azithromycin 500mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 20.minutes.ago,
      status_updated_at: 20.minutes.ago
    )

    get dashboard_charge_rn_url, params: { view: 'floor_view' }
    assert_response :success

    # medication_timers should not be loaded for floor_view
    assert_nil assigns(:medication_timers)
  end
end