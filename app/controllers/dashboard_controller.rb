class DashboardController < ApplicationController
  before_action :load_dashboard_stats
  
  def triage
    @patients = Patient.includes(:vitals, :events).in_triage
  end

  def rp
    @patients = Patient.includes(:vitals, :events).location_results_pending
  end

  def ed_rn
    @patients = Patient.includes(:vitals, :events).in_ed
  end

  def charge_rn
    @patients = Patient.includes(:vitals, :events).all
  end

  def provider
    @patients = Patient.includes(:vitals, :events).with_provider
  end
  
  private
  
  def load_dashboard_stats
    @total_waiting = Patient.waiting.count
    @avg_wait_time = Patient.waiting.average(:wait_time_minutes)&.round || 0
    @rp_utilization = calculate_rp_utilization
  end
  
  def calculate_rp_utilization
    total_patients = Patient.count
    return 0 if total_patients.zero?
    
    rp_eligible_count = Patient.where(rp_eligible: true).count
    ((rp_eligible_count.to_f / total_patients) * 100).round
  end
end
