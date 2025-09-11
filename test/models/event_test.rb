require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @patient = Patient.create!(
      first_name: "John",
      last_name: "Doe",
      age: 30,
      mrn: "ET_#{SecureRandom.hex(4)}"
    )
    
    @event = @patient.events.build(
      action: "Patient arrived",
      details: "Triage assessment initiated",
      performed_by: "Triage RN",
      category: "triage",
      time: Time.current
    )
  end

  test "should be valid with valid attributes" do
    assert @event.valid?
  end

  test "should belong to a patient" do
    @event.patient = nil
    assert_not @event.valid?
  end

  test "should require action" do
    @event.action = nil
    assert_not @event.valid?
    assert_includes @event.errors[:action], "can't be blank"
  end

  test "performed_by should be from allowed options" do
    Event::PERFORMED_BY_OPTIONS.each do |option|
      @event.performed_by = option
      assert @event.valid?, "#{option} should be valid"
    end
    
    @event.performed_by = "Invalid Person"
    assert_not @event.valid?
  end

  test "recent scope orders by time descending" do
    @patient.events.destroy_all
    
    old_event = @patient.events.create!(
      action: "First",
      performed_by: "System",
      time: 2.hours.ago
    )
    
    new_event = @patient.events.create!(
      action: "Second",
      performed_by: "System",
      time: 1.hour.ago
    )
    
    events = @patient.events.recent
    assert_equal new_event, events.first
    assert_equal old_event, events.second
  end
end