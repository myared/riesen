require "test_helper"

class PatientCheckoutTest < ActiveSupport::TestCase
  fixtures :patients, :rooms

  setup do
    ensure_application_setting
  end

  test "checkout releases assigned rp room" do
    patient = patients(:two)
    room = rooms(:rp_room_one)

    room.assign_patient(patient)
    patient.update!(ready_for_checkout: true, ready_for_checkout_at: Time.current)

    assert room.reload.status_occupied?, "room should be occupied after assignment"
    assert_equal patient, room.current_patient

    patient.checkout!(performed_by: "RP RN")

    room.reload
    assert_nil room.current_patient, "room should not have a current patient after checkout"
    assert room.status_available?, "room should become available after checkout"
    patient.reload
    assert_nil patient.room_number, "patient room should be cleared after checkout"
    assert patient.location_discharged?, "patient location status should be discharged"
  end

  test "checkout handles legacy room assignment without current_patient association" do
    patient = patients(:two)
    room = rooms(:rp_room_two)

    room.update!(status: :occupied, current_patient: nil)
    patient.update!(room_number: room.number, ready_for_checkout: true, ready_for_checkout_at: Time.current)

    patient.checkout!(performed_by: "RP RN")

    assert room.reload.status_available?, "legacy room should become available after checkout"
    assert_nil room.current_patient, "legacy room should no longer reference a patient"
  end
end
