require "test_helper"

class CarePathwayClinicalEndpointTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 45,
      mrn: "CPCE_#{SecureRandom.hex(4)}",
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

    @endpoint = CarePathwayClinicalEndpoint.create!(
      care_pathway: @care_pathway,
      name: "Pain Control (Score < 4)",
      description: "Patient reports pain score less than 4 out of 10"
    )
  end

  test "should be valid with valid attributes" do
    assert @endpoint.valid?
  end

  test "should require name" do
    @endpoint.name = nil
    assert_not @endpoint.valid?
    assert_includes @endpoint.errors[:name], "can't be blank"
  end

  test "should require care pathway" do
    endpoint = CarePathwayClinicalEndpoint.new(
      name: "Test Endpoint",
      description: "Test description"
    )
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:care_pathway], "must exist"
  end

  test "pending scope should return unachieved endpoints" do
    achieved_endpoint = CarePathwayClinicalEndpoint.create!(
      care_pathway: @care_pathway,
      name: "Achieved Endpoint",
      description: "This endpoint has been achieved",
      achieved: true,
      achieved_at: 10.minutes.ago
    )

    pending_endpoints = CarePathwayClinicalEndpoint.pending
    assert_includes pending_endpoints, @endpoint
    assert_not_includes pending_endpoints, achieved_endpoint
  end

  test "achieved scope should return achieved endpoints" do
    achieved_endpoint = CarePathwayClinicalEndpoint.create!(
      care_pathway: @care_pathway,
      name: "Achieved Endpoint",
      description: "This endpoint has been achieved",
      achieved: true,
      achieved_at: 10.minutes.ago
    )

    achieved_endpoints = CarePathwayClinicalEndpoint.achieved
    assert_not_includes achieved_endpoints, @endpoint
    assert_includes achieved_endpoints, achieved_endpoint
  end

  test "achieve! should mark endpoint as achieved" do
    freeze_time do
      assert_not @endpoint.achieved?

      @endpoint.achieve!("Test Nurse")

      @endpoint.reload
      assert @endpoint.achieved?
      assert_equal Time.current, @endpoint.achieved_at
      assert_equal "Test Nurse", @endpoint.achieved_by
    end
  end

  test "status should return correct status text" do
    assert_equal "Pending", @endpoint.status

    @endpoint.update!(achieved: true)
    assert_equal "Achieved", @endpoint.status
  end

  test "status_class should return correct CSS class" do
    assert_equal "endpoint-pending", @endpoint.status_class

    @endpoint.update!(achieved: true)
    assert_equal "endpoint-achieved", @endpoint.status_class
  end

  test "icon should return endpoint icon" do
    assert_equal "🎯", @endpoint.icon
  end

  test "should have predefined clinical endpoints list" do
    assert_includes CarePathwayClinicalEndpoint::CLINICAL_ENDPOINTS, "Pain Control (Score < 4)"
    assert_includes CarePathwayClinicalEndpoint::CLINICAL_ENDPOINTS, "Hemodynamic Stability"
    assert CarePathwayClinicalEndpoint::CLINICAL_ENDPOINTS.frozen?
  end
end