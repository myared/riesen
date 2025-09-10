class CarePathwayOrder < ApplicationRecord
  belongs_to :care_pathway
  
  # Order types
  enum :order_type, {
    lab: 0,
    medication: 1,
    imaging: 2
  }, prefix: true
  
  # Order status progression
  enum :status, {
    ordered: 0,
    collected: 1,
    in_lab: 2,
    resulted: 3
  }, prefix: false
  
  # Common lab orders
  LAB_ORDERS = [
    'CBC with Differential',
    'Basic Metabolic Panel',
    'Comprehensive Metabolic Panel',
    'Liver Function Tests',
    'Lipid Panel',
    'PT/INR',
    'PTT',
    'Troponin',
    'BNP',
    'D-Dimer',
    'Urinalysis',
    'Urine Culture',
    'Blood Culture',
    'Lactate',
    'Arterial Blood Gas',
    'COVID-19 PCR',
    'Rapid Strep',
    'Influenza A/B'
  ].freeze
  
  # Common medications
  MEDICATIONS = [
    'Acetaminophen 650mg PO',
    'Ibuprofen 400mg PO',
    'Morphine 2mg IV',
    'Zofran 4mg IV',
    'Normal Saline 1L IV',
    'Ceftriaxone 1g IV',
    'Azithromycin 500mg PO',
    'Prednisone 40mg PO',
    'Albuterol Nebulizer',
    'Epinephrine 0.3mg IM',
    'Nitroglycerin 0.4mg SL',
    'Aspirin 325mg PO',
    'Heparin 5000 units SC',
    'Lorazepam 1mg IV'
  ].freeze
  
  # Common imaging orders
  IMAGING_ORDERS = [
    'Chest X-Ray',
    'Abdominal X-Ray',
    'CT Head without Contrast',
    'CT Chest with PE Protocol',
    'CT Abdomen/Pelvis with Contrast',
    'MRI Brain',
    'Ultrasound Abdomen',
    'Ultrasound Lower Extremity DVT',
    'Echocardiogram',
    'EKG'
  ].freeze
  
  validates :name, presence: true
  validates :order_type, presence: true
  validates :status, presence: true
  
  scope :labs, -> { order_type_lab }
  scope :medications, -> { order_type_medication }
  scope :imaging, -> { order_type_imaging }
  scope :pending, -> { where.not(status: :resulted) }
  scope :completed, -> { where(status: :resulted) }
  
  # Progress to next status
  def advance_status!
    return false if resulted?
    
    next_status = case status.to_sym
                  when :ordered then :collected
                  when :collected then :in_lab
                  when :in_lab then :resulted
                  else
                    return false
                  end
    
    update!(
      status: next_status,
      status_updated_at: Time.current,
      status_updated_by: Current.user&.name
    )
  end
  
  # Check if order is complete
  def complete?
    resulted?
  end
  
  # Get status label
  def status_label
    case status.to_sym
    when :ordered then 'Ordered'
    when :collected then 'Collected'
    when :in_lab then 'In Lab'
    when :resulted then 'Resulted'
    end
  end
  
  # Get order icon based on type
  def type_icon
    case order_type.to_sym
    when :lab then '🧪'
    when :medication then '💊'
    when :imaging then '📷'
    end
  end
end