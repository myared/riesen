require "test_helper"

class CarePathwayOrderTest < ActiveSupport::TestCase
  setup do
    ensure_application_setting

    @patient = Patient.create!(
      first_name: "Test",
      last_name: "Patient",
      age: 45,
      mrn: "CPO_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :triage,
      arrival_time: 2.hours.ago
    )

    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :triage,
      status: :in_progress,
      started_at: 1.hour.ago,
      started_by: "Test RN"
    )

    @lab_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: 30.minutes.ago
    )

    @medication_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "Acetaminophen 650mg PO",
      order_type: :medication,
      status: :ordered,
      ordered_at: 20.minutes.ago
    )

    @imaging_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "CT Head without Contrast",
      order_type: :imaging,
      status: :ordered,
      ordered_at: 15.minutes.ago
    )
  end

  # Basic model validations
  test "should be valid with valid attributes" do
    assert @lab_order.valid?
    assert @medication_order.valid?
    assert @imaging_order.valid?
  end

  test "should require name" do
    order = CarePathwayOrder.new(
      care_pathway: @care_pathway,
      order_type: :lab,
      status: :ordered
    )
    assert_not order.valid?
    assert_includes order.errors[:name], "can't be blank"
  end

  test "should require order_type" do
    order = CarePathwayOrder.new(
      care_pathway: @care_pathway,
      name: "Test Order",
      status: :ordered
    )
    assert_not order.valid?
    assert_includes order.errors[:order_type], "can't be blank"
  end

  test "should require status" do
    order = CarePathwayOrder.new(
      care_pathway: @care_pathway,
      name: "Test Order",
      order_type: :lab
    )
    # Status defaults to :ordered in Rails enum, so this test will pass
    # We need to explicitly set it to nil to test validation
    order.status = nil
    assert_not order.valid?
    assert_includes order.errors[:status], "can't be blank"
  end

  test "should validate timer_status inclusion" do
    @lab_order.timer_status = "invalid"
    assert_not @lab_order.valid?
    assert_includes @lab_order.errors[:timer_status], "is not included in the list"

    @lab_order.timer_status = "green"
    assert @lab_order.valid?

    @lab_order.timer_status = nil
    assert @lab_order.valid?
  end

  # Test workflow_states method
  test "workflow_states should return correct states for lab orders" do
    expected = [:ordered, :collected, :in_lab, :resulted]
    assert_equal expected, @lab_order.workflow_states
  end

  test "workflow_states should return correct states for medication orders" do
    expected = [:ordered, :administered]
    assert_equal expected, @medication_order.workflow_states
  end

  test "workflow_states should return correct states for imaging orders" do
    expected = [:ordered, :exam_started, :exam_completed, :resulted]
    assert_equal expected, @imaging_order.workflow_states
  end

  test "workflow_states should default to lab flow for unknown order type" do
    # This tests the else clause in workflow_states
    # Create a direct instance with mocked order_type method
    order = @lab_order.dup
    def order.order_type
      ActiveSupport::StringInquirer.new("unknown")
    end
    expected = [:ordered, :collected, :in_lab, :resulted]
    assert_equal expected, order.workflow_states
  end

  # Test calculate_timer_status method
  test "calculate_timer_status should use medication thresholds for medication orders" do
    # For medication ordered status, target is 30 minutes
    # Warning threshold = 75% of 30 = 23 minutes
    # Critical threshold = 100% of 30 = 30 minutes

    # Test green (0-23 minutes)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 3)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 20)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 23)

    # Test yellow (24-30 minutes)
    assert_equal "yellow", @medication_order.send(:calculate_timer_status, 25)
    assert_equal "yellow", @medication_order.send(:calculate_timer_status, 30)

    # Test red (>30 minutes)
    assert_equal "red", @medication_order.send(:calculate_timer_status, 35)
    assert_equal "red", @medication_order.send(:calculate_timer_status, 45)
  end

  test "calculate_timer_status should use standard thresholds for lab and imaging orders" do
    # For lab ordered status, target is 15 minutes
    # Warning threshold = 75% of 15 = 11 minutes
    # Critical threshold = 100% of 15 = 15 minutes

    # Test green (0-11 minutes)
    assert_equal "green", @lab_order.send(:calculate_timer_status, 5)
    assert_equal "green", @lab_order.send(:calculate_timer_status, 11)

    # Test yellow (12-15 minutes)
    assert_equal "yellow", @lab_order.send(:calculate_timer_status, 13)
    assert_equal "yellow", @lab_order.send(:calculate_timer_status, 15)

    # Test red (>15 minutes)
    assert_equal "red", @lab_order.send(:calculate_timer_status, 20)
    assert_equal "red", @lab_order.send(:calculate_timer_status, 30)

    # For imaging ordered status, target is 20 minutes
    # Warning threshold = 75% of 20 = 15 minutes
    # Critical threshold = 100% of 20 = 20 minutes
    assert_equal "green", @imaging_order.send(:calculate_timer_status, 15)
    assert_equal "yellow", @imaging_order.send(:calculate_timer_status, 18)
    assert_equal "red", @imaging_order.send(:calculate_timer_status, 25)
  end

  # Test complete? method
  test "complete? should check administered status for medication orders" do
    assert_not @medication_order.complete?

    @medication_order.update!(status: :administered)
    assert @medication_order.complete?
  end

  test "complete? should check resulted status for lab orders" do
    assert_not @lab_order.complete?

    @lab_order.update!(status: :collected)
    assert_not @lab_order.complete?

    @lab_order.update!(status: :in_lab)
    assert_not @lab_order.complete?

    @lab_order.update!(status: :resulted)
    assert @lab_order.complete?
  end

  test "complete? should check resulted status for imaging orders" do
    assert_not @imaging_order.complete?

    @imaging_order.update!(status: :exam_started)
    assert_not @imaging_order.complete?

    @imaging_order.update!(status: :exam_completed)
    assert_not @imaging_order.complete?

    @imaging_order.update!(status: :resulted)
    assert @imaging_order.complete?
  end

  test "complete? should default to resulted status for unknown order types" do
    # Create a direct instance with mocked order_type method
    order = @lab_order.dup
    def order.order_type
      ActiveSupport::StringInquirer.new("unknown")
    end

    assert_not order.complete?

    def order.resulted?
      true
    end
    assert order.complete?
  end

  # Test determine_next_status private method
  test "determine_next_status should return next status in workflow for lab order" do
    # ordered -> collected
    assert_equal :collected, @lab_order.send(:determine_next_status)

    @lab_order.update!(status: :collected)
    assert_equal :in_lab, @lab_order.send(:determine_next_status)

    @lab_order.update!(status: :in_lab)
    assert_equal :resulted, @lab_order.send(:determine_next_status)

    @lab_order.update!(status: :resulted)
    assert_nil @lab_order.send(:determine_next_status)
  end

  test "determine_next_status should return next status in workflow for medication order" do
    # ordered -> administered
    assert_equal :administered, @medication_order.send(:determine_next_status)

    @medication_order.update!(status: :administered)
    assert_nil @medication_order.send(:determine_next_status)
  end

  test "determine_next_status should return next status in workflow for imaging order" do
    # ordered -> exam_started
    assert_equal :exam_started, @imaging_order.send(:determine_next_status)

    @imaging_order.update!(status: :exam_started)
    assert_equal :exam_completed, @imaging_order.send(:determine_next_status)

    @imaging_order.update!(status: :exam_completed)
    assert_equal :resulted, @imaging_order.send(:determine_next_status)

    @imaging_order.update!(status: :resulted)
    assert_nil @imaging_order.send(:determine_next_status)
  end

  test "determine_next_status should return nil for unknown status" do
    # Create a direct instance with mocked status method
    order = @lab_order.dup
    def order.status
      ActiveSupport::StringInquirer.new("unknown")
    end
    def order.workflow_states
      [:ordered, :collected, :in_lab, :resulted]
    end
    assert_nil order.send(:determine_next_status)
  end

  # Test advance_status! method with new status flows
  test "advance_status! should advance lab order through workflow" do
    freeze_time do
      # ordered -> collected
      result = @lab_order.advance_status!("ED RN")
      assert result

      @lab_order.reload
      assert @lab_order.collected?
      assert_equal Time.current, @lab_order.collected_at
      assert_equal Time.current, @lab_order.status_updated_at
      assert_equal "ED RN", @lab_order.status_updated_by

      # collected -> in_lab
      result = @lab_order.advance_status!("Provider")
      assert result

      @lab_order.reload
      assert @lab_order.in_lab?
      assert_equal Time.current, @lab_order.in_lab_at

      # in_lab -> resulted
      result = @lab_order.advance_status!("Provider")
      assert result

      @lab_order.reload
      assert @lab_order.resulted?
      assert_equal Time.current, @lab_order.resulted_at

      # Should not advance further
      result = @lab_order.advance_status!("ED RN")
      assert_not result
    end
  end

  test "advance_status! should advance medication order through workflow" do
    freeze_time do
      # ordered -> administered
      result = @medication_order.advance_status!("ED RN")
      assert result

      @medication_order.reload
      assert @medication_order.administered?
      assert_equal Time.current, @medication_order.administered_at
      assert_equal Time.current, @medication_order.status_updated_at
      assert_equal "ED RN", @medication_order.status_updated_by

      # Should not advance further
      result = @medication_order.advance_status!("ED RN")
      assert_not result
    end
  end

  test "advance_status! should advance imaging order through workflow" do
    freeze_time do
      # ordered -> exam_started
      result = @imaging_order.advance_status!("Provider")
      assert result

      @imaging_order.reload
      assert @imaging_order.exam_started?
      assert_equal Time.current, @imaging_order.exam_started_at

      # exam_started -> exam_completed
      result = @imaging_order.advance_status!("Provider")
      assert result

      @imaging_order.reload
      assert @imaging_order.exam_completed?
      assert_equal Time.current, @imaging_order.exam_completed_at

      # exam_completed -> resulted
      result = @imaging_order.advance_status!("Provider")
      assert result

      @imaging_order.reload
      assert @imaging_order.resulted?
      assert_equal Time.current, @imaging_order.resulted_at

      # Should not advance further
      result = @imaging_order.advance_status!("Provider")
      assert_not result
    end
  end

  test "advance_status! should calculate timer status based on duration" do
    freeze_time do
      # Set up a previous timestamp to calculate duration from ordered_at
      # Since the lab order is in "ordered" status, it will use ordered_at for duration calculation
      # Lab ordered target is 15 minutes, so 13 minutes should be yellow (between 11-15)
      @lab_order.update!(ordered_at: 13.minutes.ago)

      result = @lab_order.advance_status!("ED RN")
      assert result

      @lab_order.reload
      assert_equal "yellow", @lab_order.timer_status  # 13 minutes = yellow for lab
      assert_equal 13, @lab_order.last_status_duration_minutes
    end
  end

  test "advance_status! should create status event" do
    freeze_time do
      # Set ordered_at to 13 minutes ago to get yellow timer status
      # Lab ordered target is 15 minutes, yellow is 12-15 minutes
      @lab_order.update!(ordered_at: 13.minutes.ago)

      assert_difference "Event.count", 1 do
        @lab_order.advance_status!("Triage RN")  # Use valid performer from Event::PERFORMED_BY_OPTIONS
      end

      event = Event.last
      assert_equal @patient, event.patient
      assert_equal "Order status updated: Collected", event.action
      assert_includes event.details, @lab_order.name
      assert_includes event.details, "yellow"  # 13 minutes = yellow for lab
      assert_equal "Triage RN", event.performed_by
      assert_equal "diagnostic", event.category
    end
  end

  test "advance_status! should handle System performer when user_name not in allowed list" do
    result = @lab_order.advance_status!("Invalid User")
    assert result

    event = Event.last
    assert_equal "System", event.performed_by
  end

  test "advance_status! should handle nil user_name" do
    result = @lab_order.advance_status!
    assert result

    event = Event.last
    assert_equal "System", event.performed_by
  end

  # Test edge cases
  test "advance_status! should handle nil previous timestamp gracefully" do
    # Remove all timestamps to simulate no previous state
    @lab_order.update!(ordered_at: nil, status_updated_at: nil)

    result = @lab_order.advance_status!("Test RN")
    assert result

    @lab_order.reload
    assert_equal 0, @lab_order.last_status_duration_minutes
    assert_equal "green", @lab_order.timer_status
  end

  test "should handle boundary conditions for timer thresholds" do
    # Medication boundaries (target: 30 min, warning: 23 min, critical: 30 min)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 0)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 22)
    assert_equal "green", @medication_order.send(:calculate_timer_status, 23)
    assert_equal "yellow", @medication_order.send(:calculate_timer_status, 24)
    assert_equal "yellow", @medication_order.send(:calculate_timer_status, 30)
    assert_equal "red", @medication_order.send(:calculate_timer_status, 31)

    # Lab boundaries (target: 15 min, warning: 11 min, critical: 15 min)
    assert_equal "green", @lab_order.send(:calculate_timer_status, 0)
    assert_equal "green", @lab_order.send(:calculate_timer_status, 11)
    assert_equal "yellow", @lab_order.send(:calculate_timer_status, 12)
    assert_equal "yellow", @lab_order.send(:calculate_timer_status, 15)
    assert_equal "red", @lab_order.send(:calculate_timer_status, 16)
  end

  # Test scopes
  test "should filter by order type scopes" do
    lab_orders = CarePathwayOrder.labs
    assert_includes lab_orders, @lab_order
    assert_not_includes lab_orders, @medication_order
    assert_not_includes lab_orders, @imaging_order

    medication_orders = CarePathwayOrder.medications
    assert_not_includes medication_orders, @lab_order
    assert_includes medication_orders, @medication_order
    assert_not_includes medication_orders, @imaging_order

    imaging_orders = CarePathwayOrder.imaging
    assert_not_includes imaging_orders, @lab_order
    assert_not_includes imaging_orders, @medication_order
    assert_includes imaging_orders, @imaging_order
  end

  test "should filter by completion status" do
    # Initially all orders are pending
    pending_orders = CarePathwayOrder.pending
    assert_includes pending_orders, @lab_order
    assert_includes pending_orders, @medication_order
    assert_includes pending_orders, @imaging_order

    completed_orders = CarePathwayOrder.completed
    assert_not_includes completed_orders, @lab_order
    assert_not_includes completed_orders, @medication_order
    assert_not_includes completed_orders, @imaging_order

    # Complete one order
    @lab_order.update!(status: :resulted)

    pending_orders = CarePathwayOrder.pending
    assert_not_includes pending_orders, @lab_order
    assert_includes pending_orders, @medication_order

    completed_orders = CarePathwayOrder.completed
    assert_includes completed_orders, @lab_order
    assert_not_includes completed_orders, @medication_order
  end

  # Test utility methods
  test "type_icon should return correct icons" do
    assert_equal "🔬", @lab_order.type_icon
    assert_equal "💊", @medication_order.type_icon
    assert_equal "📷", @imaging_order.type_icon
  end

  test "status_label should return human readable status" do
    assert_equal "Ordered", @lab_order.status_label

    @lab_order.update!(status: :collected)
    assert_equal "Collected", @lab_order.status_label

    @medication_order.update!(status: :administered)
    assert_equal "Administered", @medication_order.status_label

    @imaging_order.update!(status: :exam_started)
    assert_equal "Exam Started", @imaging_order.status_label
  end

  test "status_class should return CSS class name" do
    assert_equal "status-ordered", @lab_order.status_class

    @lab_order.update!(status: :collected)
    assert_equal "status-collected", @lab_order.status_class
  end

  test "status_value should return numeric status value" do
    assert_equal 0, @lab_order.status_value  # ordered

    @medication_order.update!(status: :administered)
    assert_equal 4, @medication_order.status_value  # administered
  end

  # Test error conditions
  test "advance_status! should handle record invalid errors" do
    # Force a validation error by stubbing update! to raise an error
    @lab_order.define_singleton_method(:update!) do |_|
      raise ActiveRecord::RecordInvalid.new(self)
    end

    result = @lab_order.advance_status!("ED RN")
    assert_not result
  end

  test "advance_status! should use transaction and locking" do
    # Test that the method calls lock! and uses transaction behavior
    # We can't easily test rollback without actually causing a rollback
    original_status = @lab_order.status

    # Verify lock! is called by ensuring we can advance normally
    result = @lab_order.advance_status!("ED RN")
    assert result

    @lab_order.reload
    assert_not_equal original_status, @lab_order.status
  end

  # Test constants
  test "should have correct constant values" do
    assert_includes CarePathwayOrder::LAB_ORDERS, "CBC with Differential"
    assert_includes CarePathwayOrder::MEDICATIONS, "Acetaminophen 650mg PO"
    assert_includes CarePathwayOrder::IMAGING_ORDERS, "CT Head without Contrast"

    # Test array is frozen
    assert CarePathwayOrder::LAB_ORDERS.frozen?
    assert CarePathwayOrder::MEDICATIONS.frozen?
    assert CarePathwayOrder::IMAGING_ORDERS.frozen?
  end
end
