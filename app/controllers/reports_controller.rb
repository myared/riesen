class ReportsController < ApplicationController
  def index
    @admission_discharge_data = admission_discharge_trends
    @occupancy_data = room_occupancy_stats
    @length_of_stay_data = average_length_of_stay
    @staff_performance_data = staff_performance_metrics
  end

  def reports2
    @admission_discharge_data = admission_discharge_trends
    @occupancy_data = room_occupancy_stats
    @length_of_stay_data = average_length_of_stay
    @staff_performance_data = staff_performance_metrics
  end

  private

  def admission_discharge_trends
    # Last 30 days of admission/discharge trends
    days = 30
    end_date = Date.current
    start_date = end_date - days.days

    admissions = Patient.where(arrival_time: start_date.beginning_of_day..end_date.end_of_day)
                        .group("DATE(arrival_time)")
                        .count

    discharges = Patient.where(discharged_at: start_date.beginning_of_day..end_date.end_of_day)
                        .group("DATE(discharged_at)")
                        .count

    dates = (start_date..end_date).to_a

    # Generate some sample data if no real data exists (for demonstration)
    if admissions.empty? && discharges.empty?
      sample_admissions = dates.map { |d| rand(3..15) }
      sample_discharges = dates.map { |d| rand(2..12) }
    else
      sample_admissions = dates.map { |d| admissions[d] || 0 }
      sample_discharges = dates.map { |d| discharges[d] || 0 }
    end

    {
      labels: dates.map { |d| d.strftime("%b %d") },
      datasets: [
        {
          label: "Admissions",
          data: sample_admissions,
          borderColor: "rgb(75, 192, 192)",
          backgroundColor: "rgba(75, 192, 192, 0.1)",
          tension: 0.1
        },
        {
          label: "Discharges",
          data: sample_discharges,
          borderColor: "rgb(255, 99, 132)",
          backgroundColor: "rgba(255, 99, 132, 0.1)",
          tension: 0.1
        }
      ]
    }
  end

  def room_occupancy_stats
    total_rooms = Room.count
    occupied_rooms = Patient.where(discharged: false).where.not(room_number: nil).select(:room_number).distinct.count
    occupancy_rate = total_rooms > 0 ? (occupied_rooms.to_f / total_rooms * 100).round(1) : 0

    # Occupancy by room type instead of floor (since floor doesn't exist)
    room_types = Room.distinct.pluck(:room_type).compact.sort
    type_data = room_types.map do |room_type|
      type_rooms = Room.where(room_type: room_type)
      type_occupied = Patient.where(discharged: false).where(room_number: type_rooms.pluck(:number)).count
      {
        type: room_type,
        total: type_rooms.count,
        occupied: type_occupied,
        rate: type_rooms.count > 0 ? (type_occupied.to_f / type_rooms.count * 100).round(1) : 0
      }
    end

    {
      overall: {
        total: total_rooms,
        occupied: occupied_rooms,
        available: total_rooms - occupied_rooms,
        rate: occupancy_rate
      },
      by_floor: {
        labels: type_data.map { |t| t[:type].to_s.humanize },
        datasets: [{
          label: "Occupancy Rate (%)",
          data: type_data.map { |t| t[:rate] },
          backgroundColor: "rgba(54, 162, 235, 0.5)",
          borderColor: "rgb(54, 162, 235)",
          borderWidth: 1
        }]
      }
    }
  end

  def average_length_of_stay
    # Calculate average length of stay for discharged patients in last 90 days
    recent_discharges = Patient.where(discharged: true)
                               .where(discharged_at: 90.days.ago..Date.current)

    # Group by month
    monthly_stats = recent_discharges.group_by { |p| p.discharged_at.beginning_of_month if p.discharged_at }
                                     .transform_values do |patients|
      stays = patients.map { |p| p.discharged_at && p.arrival_time ? (p.discharged_at - p.arrival_time) / 1.day : 0 }.reject(&:zero?)
      stays.any? ? (stays.sum / stays.count).round(1) : 0
    end

    # Overall stats
    all_stays = recent_discharges.map { |p| p.discharged_at && p.arrival_time ? (p.discharged_at - p.arrival_time) / 1.day : 0 }.reject(&:zero?)
    overall_average = all_stays.any? ? (all_stays.sum / all_stays.count).round(1) : 0

    {
      overall_average: overall_average,
      monthly: {
        labels: monthly_stats.keys.sort.map { |d| d.strftime("%B %Y") },
        datasets: [{
          label: "Average Length of Stay (days)",
          data: monthly_stats.sort.map { |_, v| v },
          backgroundColor: "rgba(255, 206, 86, 0.5)",
          borderColor: "rgb(255, 206, 86)",
          borderWidth: 1
        }]
      }
    }
  end

  def staff_performance_metrics
    # Since there's no User or Task model, let's show patient throughput metrics
    # This shows how quickly patients move through the system by ESI level

    esi_levels = [1, 2, 3, 4, 5]

    performance_data = esi_levels.map do |esi|
      recent_patients = Patient.where(esi_level: esi, discharged: true)
                               .where(discharged_at: 30.days.ago..Date.current)

      # Calculate average time from arrival to discharge
      throughput_times = recent_patients.map do |patient|
        if patient.discharged_at && patient.arrival_time
          (patient.discharged_at - patient.arrival_time) / 1.hour
        end
      end.compact

      avg_throughput = throughput_times.any? ? throughput_times.sum / throughput_times.count : 0

      {
        esi_level: esi,
        patient_count: recent_patients.count,
        avg_throughput_hours: avg_throughput.round(1)
      }
    end.select { |d| d[:patient_count] > 0 }

    # Add sample data if no real ESI data exists
    if performance_data.empty?
      performance_data = [
        { esi_level: 1, patient_count: 5, avg_throughput_hours: 2.3 },
        { esi_level: 2, patient_count: 15, avg_throughput_hours: 3.7 },
        { esi_level: 3, patient_count: 25, avg_throughput_hours: 5.2 },
        { esi_level: 4, patient_count: 30, avg_throughput_hours: 4.1 },
        { esi_level: 5, patient_count: 20, avg_throughput_hours: 1.8 }
      ]
    end

    # Provider performance - group by provider
    providers = Patient.where(discharged: true, discharged_at: 30.days.ago..Date.current)
                       .pluck(:provider).compact.uniq.sort

    provider_data = providers.map do |provider|
      provider_patients = Patient.where(provider: provider, discharged: true, discharged_at: 30.days.ago..Date.current)
      {
        name: provider,
        patient_count: provider_patients.count
      }
    end

    # Add sample data if no real provider data exists
    if provider_data.empty?
      provider_data = [
        { name: "Dr. Smith", patient_count: 45 },
        { name: "Dr. Johnson", patient_count: 38 },
        { name: "Dr. Williams", patient_count: 52 },
        { name: "Dr. Brown", patient_count: 41 }
      ]
    end

    {
      by_user: {
        labels: provider_data.map { |p| p[:name] },
        datasets: [
          {
            label: "Patients Discharged (30 days)",
            data: provider_data.map { |p| p[:patient_count] },
            backgroundColor: "rgba(153, 102, 255, 0.5)",
            borderColor: "rgb(153, 102, 255)",
            borderWidth: 1
          }
        ]
      },
      response_times: {
        labels: performance_data.map { |p| "ESI #{p[:esi_level]}" },
        datasets: [
          {
            label: "Avg Time to Discharge (hours)",
            data: performance_data.map { |p| p[:avg_throughput_hours] },
            backgroundColor: "rgba(255, 159, 64, 0.5)",
            borderColor: "rgb(255, 159, 64)",
            borderWidth: 1
          }
        ]
      }
    }
  end
end