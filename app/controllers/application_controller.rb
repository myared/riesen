class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_header_data

  private

  def set_header_data
    @active_patient_count = Patient.where.not(location_status: :discharged).count
    @current_role = controller_name == 'dashboard' ? action_name : 'triage'
  end
end
