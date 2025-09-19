require "test_helper"

class SimplifiedTaskListViewTest < ActionView::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 30,
      mrn: "VIEW_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :waiting_room,
      arrival_time: Time.current
    )
  end

  test "renders 'No tasks pending' when patient has no tasks" do
    # Create patient with no active tasks - already triaged and in room
    @patient.update!(
      location_status: :ed_room,
      triage_completed_at: 1.hour.ago,
      arrival_time: 2.hours.ago
    )

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "triage" }
    )

    assert_includes html, "No tasks pending"
    assert_includes html, "no-tasks"
  end

  test "renders task list when patient has check-in task" do
    # Create patient with check-in task
    @patient.update!(
      arrival_time: 25.minutes.ago,
      triage_completed_at: nil,
      location_status: :waiting_room
    )

    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress
    )

    pathway.care_pathway_steps.create!(
      name: 'Check-In',
      sequence: 1,
      completed: false
    )

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "triage" }
    )

    # Should render task list container
    assert_includes html, "task-list"

    # Should render check-in task
    assert_includes html, "Check In"

    # Should show elapsed time
    assert_includes html, "25m"

    # Should include status classes (25 min with 10 min target should be red)
    assert_includes html, "task-red"
    assert_includes html, "task-indicator-red"
  end

  test "renders clickable task links when care_pathway_id is present" do
    @patient.update!(location_status: :ed_room)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    order = pathway.care_pathway_orders.create!(
      name: "CBC Lab Results",
      order_type: :lab,
      status: :ordered,
      ordered_at: 20.minutes.ago  # Should be red (20 > 15 min lab target)
    )

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "ed_rn" }
    )

    # Should render as clickable link
    assert_includes html, "<a"
    assert_includes html, "referrer=ed_rn"
    assert_includes html, "CBC Lab Results"
  end

  test "renders non-clickable task items when care_pathway_id is nil" do
    @patient.update!(
      arrival_time: 1.hour.ago,
      triage_completed_at: nil,
      location_status: :waiting_room
    )

    # Without a pathway, patient gets a fallback "Triage" task with nil care_pathway_id
    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "triage" }
    )

    # Should render as div, not link for triage fallback
    assert_includes html, '<div class="task-item'
    assert_includes html, "Triage"
  end

  test "renders different status colors correctly" do
    @patient.update!(location_status: :ed_room)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Create orders with different statuses
    green_order = pathway.care_pathway_orders.create!(
      name: "Green Lab",
      order_type: :lab,
      status: :ordered,
      ordered_at: 5.minutes.ago  # Green (5 < 11 min warning threshold for 15 min target)
    )

    red_order = pathway.care_pathway_orders.create!(
      name: "Red Med",
      order_type: :medication,
      status: :ordered,
      ordered_at: 35.minutes.ago  # Red (35 > 30 min med target)
    )

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "provider" }
    )

    # Should include status classes
    assert_includes html, "task-red"
    assert_includes html, "task-green"

    # Should include indicator classes
    assert_includes html, "task-indicator-red"
    assert_includes html, "task-indicator-green"
  end

  test "handles empty task list gracefully" do
    # Patient with no active tasks - already triaged and in room
    @patient.update!(
      location_status: :ed_room,
      triage_completed_at: 1.hour.ago,
      arrival_time: 2.hours.ago
    )

    # Should not raise error
    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "charge_rn" }
    )

    assert_includes html, "simplified-tasks"
    assert_includes html, "No tasks pending"
  end

  test "renders task names with special characters correctly" do
    @patient.update!(location_status: :ed_room)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    order = pathway.care_pathway_orders.create!(
      name: "💊 Acetaminophen 650mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 5.minutes.ago
    )

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "ed_rn" }
    )

    # Should properly escape and render special characters
    assert_includes html, "💊 Acetaminophen 650mg PO"
  end

  test "limits number of tasks displayed" do
    @patient.update!(location_status: :ed_room)

    pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress
    )

    # Create 6 orders but only 4 should be displayed
    # Note: tasks are sorted by priority then elapsed time, so oldest (most overdue) show first
    6.times do |i|
      pathway.care_pathway_orders.create!(
        name: "Order #{i + 1}",
        order_type: :lab,
        status: :ordered,
        ordered_at: (20 + i).minutes.ago
      )
    end

    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: "triage" }
    )

    # Should show 4 tasks (default limit), ordered by most overdue first
    # Order 6 (25 min) should be most overdue and first
    assert_includes html, "Order 6"
    assert_includes html, "Order 5"
    assert_includes html, "Order 4"
    assert_includes html, "Order 3"
    # Should NOT include the least overdue orders
    assert_not_includes html, "Order 1"
    assert_not_includes html, "Order 2"
  end

  test "renders different referrer parameters correctly" do
    @patient.update!(
      arrival_time: 20.minutes.ago,
      triage_completed_at: nil,
      location_status: :waiting_room
    )

    pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress
    )

    # Add check-in step so there's a task with a care_pathway_id
    pathway.care_pathway_steps.create!(
      name: 'Check-In',
      sequence: 1,
      completed: false
    )

    # Test different referrer values
    referrers = ["triage", "ed_rn", "provider", "charge_rn"]

    referrers.each do |referrer|
      html = render(
        partial: "shared/simplified_task_list",
        locals: { patient: @patient, referrer: referrer }
      )

      assert_includes html, "referrer=#{referrer}"
    end
  end

  test "handles nil referrer gracefully" do
    @patient.update!(
      arrival_time: 20.minutes.ago,
      triage_completed_at: nil,
      location_status: :waiting_room
    )

    # Without a triage pathway, patient gets fallback "Triage" task
    # Should not raise error with nil referrer
    html = render(
      partial: "shared/simplified_task_list",
      locals: { patient: @patient, referrer: nil }
    )

    assert_includes html, "Triage"
  end
end