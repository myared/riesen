class ReportsController < ApplicationController
  def index
    @patient_flow_data = patient_flow_trends
    @staff_allocation_data = staff_allocation
    @wait_times_data = average_wait_times
    @rp_utilization_data = rp_utilization
    @bed_occupancy_data = bed_occupancy
    @staff_availability_data = staff_availability
  end

  private

  def patient_flow_trends
    # Hourly arrivals vs discharges - Today
    hours = ['8AM', '10AM', '12PM', '2PM', '4PM', '6PM', '8PM']

    {
      labels: hours,
      datasets: [
        {
          label: 'Arrivals',
          data: [8, 12, 18, 14, 20, 25, 15],
          borderColor: '#26a69a',
          backgroundColor: 'rgba(38, 166, 154, 0.1)',
          tension: 0.4
        },
        {
          label: 'Discharges',
          data: [5, 8, 10, 12, 15, 18, 22],
          borderColor: '#ef5350',
          backgroundColor: 'rgba(239, 83, 80, 0.1)',
          tension: 0.4
        }
      ]
    }
  end

  def staff_allocation
    # Current shift staffing by department
    {
      labels: ['Triage', 'Trauma', 'General', 'Pediat', 'Cardia', 'Radiol'],
      datasets: [
        {
          label: 'Nurses',
          data: [3, 8, 12, 4, 6, 2],
          backgroundColor: '#26a69a',
        },
        {
          label: 'Doctors',
          data: [1, 3, 4, 2, 2, 1],
          backgroundColor: '#ef5350',
        }
      ]
    }
  end

  def average_wait_times
    # Wait times by triage level (minutes) - area chart
    hours = ['8AM', '10AM', '12PM', '2PM', '4PM', '6PM', '8PM']

    {
      labels: hours,
      datasets: [
        {
          label: 'ESI 1-2',
          data: [5, 8, 10, 8, 5, 12, 10],
          borderColor: '#ef5350',
          backgroundColor: 'rgba(239, 83, 80, 0.3)',
          fill: true,
          tension: 0.4
        },
        {
          label: 'ESI 3',
          data: [20, 25, 35, 30, 28, 40, 35],
          borderColor: '#facc15',
          backgroundColor: 'rgba(250, 204, 21, 0.3)',
          fill: true,
          tension: 0.4
        },
        {
          label: 'ESI 4-5',
          data: [45, 55, 70, 65, 60, 85, 75],
          borderColor: '#26a69a',
          backgroundColor: 'rgba(38, 166, 154, 0.3)',
          fill: true,
          tension: 0.4
        }
      ]
    }
  end

  def rp_utilization
    # RP Utilization over time (line graph)
    hours = ['8AM', '10AM', '12PM', '2PM', '4PM', '6PM', '8PM']

    {
      labels: hours,
      datasets: [
        {
          label: 'RP Utilization %',
          data: [65, 78, 85, 72, 88, 92, 75],
          borderColor: '#0d47a1',
          backgroundColor: 'rgba(13, 71, 161, 0.1)',
          tension: 0.4,
          fill: true
        }
      ]
    }
  end

  def bed_occupancy
    # Current capacity utilization - using horizontal bar
    occupied = 84
    available = 16

    {
      labels: ['Occupied', 'Available'],
      datasets: [{
        label: 'Beds',
        data: [occupied, available],
        backgroundColor: [
          '#ef5350',
          '#26a69a'
        ],
        borderWidth: 0
      }]
    }
  end

  def staff_availability
    # Current staff status overview - using horizontal bar
    active = 65
    on_break = 15
    available = 13

    {
      labels: ['Active', 'On Break', 'Available'],
      datasets: [{
        label: 'Staff',
        data: [active, on_break, available],
        backgroundColor: [
          '#26a69a',
          '#facc15',
          '#0d47a1'
        ],
        borderWidth: 0
      }]
    }
  end
end
