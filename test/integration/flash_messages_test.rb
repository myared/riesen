require "test_helper"

class FlashMessagesTest < ActionDispatch::IntegrationTest
  setup do
    ensure_application_setting
  end

  test "rp dashboard shows alert when assign room fails" do
    Room.delete_all

    patient = Patient.create!(
      first_name: "RP",
      last_name: "Patient",
      age: 40,
      mrn: "RPFLASH#{SecureRandom.hex(3)}",
      location: "Waiting Room",
      chief_complaint: "Follow-up",
      esi_level: 3,
      rp_eligible: true,
      location_status: :needs_room_assignment,
      wait_time_minutes: 0,
      arrival_time: Time.current
    )

    post assign_room_patient_path(patient), headers: { "HTTP_REFERER" => dashboard_rp_url }
    follow_redirect!

    assert_response :success
    assert_select ".flash-message--alert", text: /Results Pending is full/
  end
end
