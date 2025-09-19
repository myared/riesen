class PatientGenerator
  # Sample data for generating realistic patients
  FIRST_NAMES = %w[
    Marcus Sarah John Emily Michael Jessica David Lisa Robert Jennifer
    William Patricia James Mary Christopher Barbara Daniel Susan Joseph Karen
    Thomas Nancy Matthew Betty Andrew Helen Sandra Mark Steven Donna
  ].freeze
  
  LAST_NAMES = %w[
    Thompson Martinez Johnson Davis Wilson Brown Jones Garcia Miller Anderson
    Taylor Thomas Jackson White Harris Martin Rodriguez Lewis Lee Walker
    Hall Allen Young King Wright Lopez Hill Scott Green Adams Baker
  ].freeze
  
  CHIEF_COMPLAINTS = [
    'Chest pain, shortness of breath',
    'Abdominal pain x3 days, vomiting',
    'Headache, dizziness',
    'Wrist pain after fall, knee laceration',
    'Fever, cough x5 days',
    'Back pain, unable to walk',
    'Allergic reaction, hives',
    'Laceration to hand',
    'Ankle sprain',
    'Difficulty breathing',
    'Motor vehicle accident, neck pain',
    'Seizure activity',
    'Acute asthma exacerbation',
    'Syncope episode',
    'Severe dehydration',
    'Eye injury, foreign body',
    'Burn injury to arm',
    'Psychiatric evaluation needed',
    'Overdose suspected',
    'Diabetic emergency'
  ].freeze
  
  PROVIDERS = [
    'Dr. Johnson',
    'Dr. Smith',
    'Dr. Williams',
    'Dr. Brown',
    'Dr. Davis',
    'Dr. Martinez',
    'Dr. Anderson',
    'Dr. Wilson',
    nil # Some patients don't have a provider yet
  ].freeze
  
  # Weighted ESI levels to reflect realistic ED distribution
  # More ESI 3-4 patients, fewer ESI 1-2 and 5
  ESI_DISTRIBUTION = [2, 3, 3, 3, 4, 4, 4, 4, 5].freeze
  
  def generate
    Patient.new(
      first_name: FIRST_NAMES.sample,
      last_name: LAST_NAMES.sample,
      age: generate_age,
      mrn: generate_unique_mrn,
      location_status: :waiting_room,
      provider: PROVIDERS.sample,
      chief_complaint: CHIEF_COMPLAINTS.sample,
      esi_level: ESI_DISTRIBUTION.sample,
      pain_score: rand(1..10),
      arrival_time: Time.current,
      wait_time_minutes: 0,
      care_pathway: '0%',
      rp_eligible: determine_rp_eligibility
    )
  end
  
  private
  
  def generate_age
    # Weighted age distribution - more adults than children or elderly
    case rand(100)
    when 0..10 then rand(1..12)    # 10% children
    when 11..20 then rand(13..17)  # 10% adolescents
    when 21..70 then rand(18..65)  # 50% adults
    when 71..90 then rand(66..80)  # 20% elderly
    else rand(81..95)              # 10% very elderly
    end
  end
  
  def generate_unique_mrn
    loop do
      mrn = rand(1000..9999).to_s
      return mrn unless Patient.exists?(mrn: mrn)
    end
  end
  
  def determine_rp_eligibility
    # 50% chance of being RP eligible
    rand(100) < 50
  end
end