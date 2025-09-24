import { Controller } from "@hotwired/stimulus"
// Chart.js loaded via CDN, available as global 'Chart'

export default class extends Controller {
  static values = {
    type: String,
    data: Object,
    options: Object
  }

  connect() {
    this.initChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  initChart() {
    const ctx = this.element.getContext('2d')

    // Merge provided options with defaults
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          display: this.typeValue !== 'doughnut',
          position: 'top',
          labels: {
            padding: 10,
            usePointStyle: true,
            font: {
              size: 11,
              family: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
            }
          }
        },
        tooltip: {
          backgroundColor: 'rgba(0, 0, 0, 0.8)',
          padding: 10,
          cornerRadius: 4,
          displayColors: true,
          callbacks: {
            label: function(context) {
              let label = context.dataset.label || '';
              if (label) {
                label += ': ';
              }
              if (context.parsed.y !== null) {
                label += context.parsed.y.toFixed(1);
              } else if (context.raw !== null) {
                label += context.raw;
              }
              return label;
            }
          }
        }
      },
      scales: this.getScalesConfig()
    }

    const config = {
      type: this.typeValue,
      data: this.dataValue,
      options: this.hasOptionsValue ? { ...defaultOptions, ...this.optionsValue } : defaultOptions
    }

    this.chart = new Chart(ctx, config)
  }

  getScalesConfig() {
    if (this.typeValue === 'line' || this.typeValue === 'bar') {
      return {
        y: {
          beginAtZero: true,
          grid: {
            drawBorder: false,
            color: 'rgba(0, 0, 0, 0.05)'
          },
          ticks: {
            padding: 8,
            font: {
              size: 11
            }
          }
        },
        x: {
          grid: {
            display: false,
            drawBorder: false
          },
          ticks: {
            padding: 8,
            font: {
              size: 11
            }
          }
        }
      }
    } else if (this.typeValue === 'doughnut') {
      return {}
    }
    return {}
  }
}