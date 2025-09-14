require 'test_helper'

class CarePathwayOrderMedicationCompletionTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 30,
      mrn: "TEST12345",
      chief_complaint: "Test complaint",
      esi_level: 3,
      arrival_time: Time.current
    )
    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      started_at: Time.current,
      started_by: "ED RN"
    )
  end

  test "medication orders are complete when administered" do
    medication = @care_pathway.care_pathway_orders.create!(
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    assert medication.complete?, "Medication should be complete when administered"
  end

  test "lab orders are complete when resulted" do
    lab = @care_pathway.care_pathway_orders.create!(
      name: "CBC with Differential",
      order_type: :lab,
      status: :resulted,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    assert lab.complete?, "Lab should be complete when resulted"
  end

  test "imaging orders are complete when resulted" do
    imaging = @care_pathway.care_pathway_orders.create!(
      name: "X-Ray Chest",
      order_type: :imaging,
      status: :resulted,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    assert imaging.complete?, "Imaging should be complete when resulted"
  end

  test "completed scope includes administered medications" do
    medication = @care_pathway.care_pathway_orders.create!(
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    lab = @care_pathway.care_pathway_orders.create!(
      name: "CBC with Differential",
      order_type: :lab,
      status: :resulted,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    completed_orders = @care_pathway.care_pathway_orders.completed

    assert_includes completed_orders, medication, "Completed scope should include administered medications"
    assert_includes completed_orders, lab, "Completed scope should include resulted labs"
    assert_equal 2, completed_orders.count, "Should have 2 completed orders"
  end

  test "pending scope excludes administered medications" do
    # Create an administered medication
    administered_med = @care_pathway.care_pathway_orders.create!(
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    # Create an ordered (not yet administered) medication
    ordered_med = @care_pathway.care_pathway_orders.create!(
      name: "Ibuprofen 400mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    pending_orders = @care_pathway.care_pathway_orders.pending

    assert_not_includes pending_orders, administered_med, "Pending scope should exclude administered medications"
    assert_includes pending_orders, ordered_med, "Pending scope should include ordered medications"
    assert_equal 1, pending_orders.count, "Should have 1 pending order"
  end

  test "progress calculation includes administered medications as complete" do
    # Create 2 orders: 1 administered medication, 1 ordered lab
    @care_pathway.care_pathway_orders.create!(
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :administered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    @care_pathway.care_pathway_orders.create!(
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: Time.current,
      ordered_by: "ED RN"
    )

    # Progress should be 50% (1 complete out of 2)
    assert_equal 50, @care_pathway.progress_percentage, "Progress should be 50% with 1 completed order out of 2"
  end
end