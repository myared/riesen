class Room < ApplicationRecord
  belongs_to :current_patient, class_name: 'Patient', optional: true, foreign_key: 'current_patient_id'
  
  # Room types
  enum :room_type, {
    ed: 0,
    rp: 1
  }, prefix: true
  
  # Room statuses
  enum :status, {
    available: 0,
    occupied: 1,
    cleaning: 2,
    maintenance: 3
  }, prefix: true
  
  validates :number, presence: true, uniqueness: true
  validates :room_type, presence: true
  
  scope :ed_rooms, -> { room_type_ed }
  scope :rp_rooms, -> { room_type_rp }
  scope :available_rooms, -> { status_available }
  scope :occupied_rooms, -> { status_occupied }
  
  # Assign a patient to the room
  def assign_patient(patient)
    transaction do
      update!(
        current_patient: patient,
        status: :occupied,
        time_in_room: 0,
        esi_level: patient.esi_level
      )
      
      # Update patient location
      if room_type_rp?
        patient.update!(location_status: :results_pending,
                        room_number: number,
                        rp_eligibility_started_at: nil)
      else
        patient.update!(location_status: :ed_room, room_number: number)
      end
      
      # Record event
      Event.create!(
        patient: patient,
        action: "Assigned to #{number}",
        details: "Patient placed in #{room_type.upcase} room #{number}",
        performed_by: room_type_rp? ? 'RP RN' : 'ED RN',
        time: Time.current,
        category: 'administrative'
      )
    end
  end
  
  # Release the room
  def release
    transaction do
      if current_patient
        current_patient.update!(room_number: nil)
      end
      
      update!(
        current_patient: nil,
        status: :cleaning,
        esi_level: nil,
        time_in_room: nil
      )
    end
  end
  
  # Mark room as available after cleaning
  def mark_available
    update!(status: :available)
  end
  
  # Get display label for room
  def display_label
    "#{room_type.upcase}#{number.gsub(/[A-Z]+/, '')}"
  end
  
  # Check if room can accept patient
  def can_accept_patient?(patient)
    return false unless status_available?
    
    if room_type_rp?
      patient.rp_eligible?
    else
      true
    end
  end
end
