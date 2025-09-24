# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Clear existing data (order matters due to foreign keys)
NursingTask.destroy_all
Patient.destroy_all
Room.destroy_all

# Load rooms first
load Rails.root.join('db/seeds/rooms.rb')

# Create sample patients
patients_data = [
  {
    first_name: 'Marcus',
    last_name: 'Thompson',
    age: 17,
    mrn: '2001',
    location: 'Waiting Room',
    provider: 'Dr. Johnson',
    chief_complaint: 'Skateboard fall, wrist pain + knee laceration',
    esi_level: 3,
    pain_score: 8,
    arrival_time: Time.current - 12.minutes,
    wait_time_minutes: 12,
    care_pathway: '0%',
    rp_eligible: true
  },
  {
    first_name: 'Sarah',
    last_name: 'Martinez',
    age: 35,
    mrn: '2002',
    location: 'Waiting Room',
    provider: nil,
    chief_complaint: 'LLQ pain x3 days, vomiting',
    esi_level: 3,
    pain_score: 8,
    arrival_time: Time.current - 9.minutes,
    wait_time_minutes: 9,
    care_pathway: '0%',
    rp_eligible: false
  },
  {
    first_name: 'Emily',
    last_name: 'Johnson',
    age: 32,
    mrn: '2003',
    location: 'Waiting Room',
    provider: nil,
    chief_complaint: 'Severe abdominal pain, cramping',
    esi_level: 2,
    pain_score: 9,
    arrival_time: Time.current - 2.minutes,
    wait_time_minutes: 15,
    care_pathway: '0%',
    rp_eligible: false
  }
]

patients_data.each do |patient_data|
  patient = Patient.create!(patient_data)

  # Create initial vitals based on patient
  vitals_data = case patient.first_name
  when 'Marcus'
    {
      heart_rate: 95,
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 90,
      respiratory_rate: 18,
      temperature: 98.7,
      spo2: 99,
      weight: 68,
      recorded_at: patient.arrival_time
    }
  when 'Sarah'
    {
      heart_rate: 130,
      blood_pressure_systolic: 155,
      blood_pressure_diastolic: 110,
      respiratory_rate: 22,
      temperature: 103.0,
      spo2: 97,
      weight: 72,
      recorded_at: patient.arrival_time
    }
  when 'Emily'
    {
      heart_rate: 110,
      blood_pressure_systolic: 145,
      blood_pressure_diastolic: 95,
      respiratory_rate: 20,
      temperature: 99.2,
      spo2: 98,
      weight: 65,
      recorded_at: patient.arrival_time
    }
  else
    {
      heart_rate: rand(70..95),
      blood_pressure_systolic: 120,
      blood_pressure_diastolic: 80,
      respiratory_rate: 18,
      temperature: 98.6,
      spo2: 99,
      weight: 70,
      recorded_at: patient.arrival_time
    }
  end

  patient.vitals.create!(vitals_data)

  # Create initial event
  patient.events.create!(
    action: 'Patient arrived',
    details: "Chief complaint: #{patient.chief_complaint}",
    performed_by: 'Registration',
    time: patient.arrival_time,
    category: 'triage'
  )
end

puts "Created #{Patient.count} patients with vitals and events"
