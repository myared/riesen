class SettingsController < ApplicationController
  before_action :load_settings

  def index
  end

  def update
    if @settings.update(settings_params)
      redirect_to settings_path, notice: 'Settings updated successfully!'
    else
      render :index, alert: 'Failed to update settings.'
    end
  end

  private

  def load_settings
    @settings = ApplicationSetting.current
  end

  def settings_params
    params.require(:application_setting).permit(
      :ed_rooms, :rp_rooms,
      :esi_1_target, :esi_2_target, :esi_3_target, :esi_4_target, :esi_5_target,
      :medicine_ordered_target, :medicine_administered_target,
      :lab_ordered_target, :lab_collected_target, :lab_in_lab_target, :lab_resulted_target,
      :imaging_ordered_target, :imaging_exam_started_target, :imaging_exam_completed_target, :imaging_resulted_target,
      :warning_threshold_percentage, :critical_threshold_percentage
    )
  end
end
