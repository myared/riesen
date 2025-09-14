# Test script to verify medication timer functionality
require_relative 'config/environment'

puts "Testing Medication Timer Functionality for Issue #3"
puts "=" * 50

# Find or create a test patient
patient = Patient.first || Patient.create!(
  full_name: "Test Patient",
  mrn: "TEST123",
  age: 45,
  sex: "M",
  chief_complaint: "Test",
  location_status: :in_ed,
  esi_level: 3,
  arrival_time: 1.hour.ago
)

# Create a care pathway if doesn't exist
care_pathway = patient.care_pathway || CarePathway.create!(
  patient: patient,
  pathway_type: :emergency_room,
  status: :in_progress
)

# Test 1: Create medication orders with different statuses
puts "\n1. Creating medication orders..."

# Green timer (just ordered)
med1 = CarePathwayOrder.create!(
  care_pathway: care_pathway,
  name: "Morphine 2mg IV",
  order_type: :medication,
  status: :ordered,
  ordered_at: 2.minutes.ago,
  status_updated_at: 2.minutes.ago,
  ordered_by: "ED RN"
)
puts "   ✓ Created medication order (2 min ago) - should be GREEN"

# Yellow timer (6 minutes ago)
med2 = CarePathwayOrder.create!(
  care_pathway: care_pathway,
  name: "Zofran 4mg IV",
  order_type: :medication,
  status: :ordered,
  ordered_at: 7.minutes.ago,
  status_updated_at: 7.minutes.ago,
  ordered_by: "ED RN"
)
puts "   ✓ Created medication order (7 min ago) - should be YELLOW"

# Red timer (12 minutes ago)
med3 = CarePathwayOrder.create!(
  care_pathway: care_pathway,
  name: "Ibuprofen 400mg PO",
  order_type: :medication,
  status: :ordered,
  ordered_at: 12.minutes.ago,
  status_updated_at: 12.minutes.ago,
  ordered_by: "ED RN"
)
puts "   ✓ Created medication order (12 min ago) - should be RED"

# Test 2: Check workflow states
puts "\n2. Testing workflow states..."

puts "   Medication workflow states: #{med1.workflow_states.inspect}"
puts "   Expected: [:ordered, :administered]"

imaging = CarePathwayOrder.create!(
  care_pathway: care_pathway,
  name: "CT Head without Contrast",
  order_type: :imaging,
  status: :ordered,
  ordered_at: 5.minutes.ago,
  status_updated_at: 5.minutes.ago,
  ordered_by: "Provider"
)
puts "\n   Imaging workflow states: #{imaging.workflow_states.inspect}"
puts "   Expected: [:ordered, :exam_started, :exam_completed, :resulted]"

lab = CarePathwayOrder.create!(
  care_pathway: care_pathway,
  name: "CBC with Differential",
  order_type: :lab,
  status: :ordered,
  ordered_at: 10.minutes.ago,
  status_updated_at: 10.minutes.ago,
  ordered_by: "ED RN"
)
puts "\n   Lab workflow states: #{lab.workflow_states.inspect}"
puts "   Expected: [:ordered, :collected, :in_lab, :resulted]"

# Test 3: Test timer status calculation
puts "\n3. Testing timer status calculation..."

[2, 5, 7, 10, 15].each do |minutes|
  test_order = CarePathwayOrder.new(order_type: :medication)
  status = test_order.send(:calculate_timer_status, minutes)
  expected = if minutes <= 5
               "green"
             elsif minutes <= 10
               "yellow"
             else
               "red"
             end
  puts "   #{minutes} minutes: #{status} (expected: #{expected}) #{status == expected ? '✓' : '✗'}"
end

# Test 4: Test advancing status
puts "\n4. Testing status advancement..."

puts "   Medication current status: #{med1.status}"
med1.advance_status!("Test User")
puts "   After advance: #{med1.status} (should be 'administered')"
puts "   Is complete? #{med1.complete?} (should be true)"

puts "\n   Imaging current status: #{imaging.status}"
imaging.advance_status!("Test User")
puts "   After 1st advance: #{imaging.status} (should be 'exam_started')"
imaging.advance_status!("Test User")
puts "   After 2nd advance: #{imaging.status} (should be 'exam_completed')"
imaging.advance_status!("Test User")
puts "   After 3rd advance: #{imaging.status} (should be 'resulted')"
puts "   Is complete? #{imaging.complete?} (should be true)"

# Test 5: Check charge nurse medication timers
puts "\n5. Testing charge nurse medication timer data..."

# Simulate controller method
medication_orders = CarePathwayOrder.joins(care_pathway: :patient)
                                    .includes(care_pathway: :patient)
                                    .where(order_type: :medication)
                                    .where.not(status: [:administered])
                                    .order(:ordered_at)

puts "   Found #{medication_orders.count} active medication orders"

medication_orders.each do |order|
  elapsed_minutes = order.status_updated_at ? ((Time.current - order.status_updated_at) / 60).round : 0
  timer_status = if elapsed_minutes <= 5
                  'GREEN'
                elsif elapsed_minutes <= 10
                  'YELLOW'
                else
                  'RED'
                end
  puts "   - #{order.name}: #{elapsed_minutes} min (#{timer_status})"
end

puts "\n✅ All tests completed!"
puts "=" * 50
puts "\nYou can now:"
puts "1. Visit http://localhost:3000 to see the application"
puts "2. Navigate to a patient's care pathway to see medication timers"
puts "3. Check the Charge RN dashboard (Staff Tasks view) to see all medication timers"
puts "\nNote: Timers update every 10 seconds in the UI"