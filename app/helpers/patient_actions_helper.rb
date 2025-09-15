module PatientActionsHelper
  # Generates the appropriate action button for a patient based on their current state
  def patient_action_button(patient, referrer = nil)
    if patient.location_needs_room_assignment?
      room_assignment_button(patient)
    elsif patient.needs_clinical_endpoints?
      add_endpoint_button(patient, referrer)
    elsif patient.can_be_discharged?
      discharge_button(patient)
    else
      pending_button
    end
  end

  private

  def room_assignment_button(patient)
    button_to 'Assign Room',
              assign_room_patient_path(patient),
              method: :post,
              class: 'btn-action btn-primary',
              data: {
                turbo: false,
                patient_id: patient.id
              }
  end

  def add_endpoint_button(patient, referrer)
    link_to 'Add Endpoint',
            patient_care_pathway_path(patient, patient.active_care_pathway,
                                    active_tab: 'endpoints',
                                    referrer: referrer || controller_name),
            class: 'btn-action btn-warning',
            data: { turbo: false }
  end

  def discharge_button(patient)
    button_to 'Discharge',
              discharge_patient_care_pathway_path(patient, patient.active_care_pathway),
              method: :post,
              class: 'btn-action btn-success',
              data: {
                turbo: false,
                confirm: "Are you sure you want to discharge #{patient.full_name}?"
              }
  end

  def pending_button
    content_tag :span, 'Pending',
                class: 'btn-action btn-disabled',
                title: 'Complete all clinical endpoints to enable discharge'
  end
end