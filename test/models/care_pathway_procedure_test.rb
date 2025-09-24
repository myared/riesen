require "test_helper"

class CarePathwayProcedureTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 45,
      mrn: "CPP_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :ed_room,
      arrival_time: 1.hour.ago
    )

    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress,
      started_at: 30.minutes.ago,
      started_by: "Test RN"
    )

    @procedure = CarePathwayProcedure.create!(
      care_pathway: @care_pathway,
      name: "IV Access Placement"
    )
  end

  test "should be valid with valid attributes" do
    assert @procedure.valid?
  end

  test "should require name" do
    @procedure.name = nil
    assert_not @procedure.valid?
    assert_includes @procedure.errors[:name], "can't be blank"
  end

  test "should require care pathway" do
    procedure = CarePathwayProcedure.new(name: "Test Procedure")
    assert_not procedure.valid?
    assert_includes procedure.errors[:care_pathway], "must exist"
  end

  test "pending scope should return uncompleted procedures" do
    completed_procedure = CarePathwayProcedure.create!(
      care_pathway: @care_pathway,
      name: "Completed Procedure",
      completed: true,
      completed_at: 10.minutes.ago
    )

    pending_procedures = CarePathwayProcedure.pending
    assert_includes pending_procedures, @procedure
    assert_not_includes pending_procedures, completed_procedure
  end

  test "completed scope should return completed procedures" do
    completed_procedure = CarePathwayProcedure.create!(
      care_pathway: @care_pathway,
      name: "Completed Procedure",
      completed: true,
      completed_at: 10.minutes.ago
    )

    completed_procedures = CarePathwayProcedure.completed
    assert_not_includes completed_procedures, @procedure
    assert_includes completed_procedures, completed_procedure
  end

  test "complete! should mark procedure as complete" do
    freeze_time do
      assert_not @procedure.completed?

      @procedure.complete!("Test Nurse")

      @procedure.reload
      assert @procedure.completed?
      assert_equal Time.current, @procedure.completed_at
      assert_equal "Test Nurse", @procedure.completed_by
    end
  end

  test "status should return correct status text" do
    assert_equal "Pending", @procedure.status

    @procedure.update!(completed: true)
    assert_equal "Complete", @procedure.status
  end

  test "status_class should return correct CSS class" do
    assert_equal "procedure-pending", @procedure.status_class

    @procedure.update!(completed: true)
    assert_equal "procedure-completed", @procedure.status_class
  end

  test "icon should return procedure icon" do
    assert_equal "🔧", @procedure.icon
  end

  test "should have predefined procedures list" do
    assert_includes CarePathwayProcedure::PROCEDURES, "IV Access Placement"
    assert_includes CarePathwayProcedure::PROCEDURES, "Foley Catheter Insertion"
    assert CarePathwayProcedure::PROCEDURES.frozen?
  end
end