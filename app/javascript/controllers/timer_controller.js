import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "progress", "label"]
  static values = { 
    startTime: String,
    thresholds: { type: Object, default: {} },
    format: { type: String, default: "minutes" },
    targetMinutes: { type: Number, default: 30 },
    maxMinutes: { type: Number, default: 60 }
  }
  
  // Define constants for magic numbers
  static DEFAULTS = {
    WARNING_THRESHOLD: 20,
    CRITICAL_THRESHOLD: 40,
    UPDATE_INTERVAL: 1000 // 1 second
  }
  
  connect() {
    this.refresh()
    this.timer = setInterval(() => this.refresh(), this.constructor.DEFAULTS.UPDATE_INTERVAL)
  }
  
  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }
  
  refresh() {
    const elapsed = this.calculateElapsed()
    
    this.updateDisplay(elapsed)
    this.updateProgress(elapsed)
    this.updateState(elapsed)
  }
  
  calculateElapsed() {
    // If no start time provided, return 0 (backend handles this case)
    if (!this.startTimeValue || this.startTimeValue === "") {
      return {
        minutes: 0,
        seconds: 0,
        totalMs: 0
      }
    }

    const startTime = new Date(this.startTimeValue)
    const now = new Date()
    const elapsedMs = now - startTime

    return {
      minutes: Math.floor(elapsedMs / 60000),
      seconds: Math.floor((elapsedMs % 60000) / 1000),
      totalMs: elapsedMs
    }
  }
  
  updateDisplay(elapsed) {
    if (!this.hasDisplayTarget) return

    // If no start time provided, keep the backend-calculated value (don't update)
    if (!this.startTimeValue || this.startTimeValue === "") {
      return
    }

    let displayText
    if (this.formatValue === "full") {
      displayText = `${String(elapsed.minutes).padStart(2, '0')}:${String(elapsed.seconds).padStart(2, '0')}`
    } else {
      displayText = `${elapsed.minutes}m`
    }

    this.displayTarget.textContent = displayText
  }
  
  updateProgress(elapsed) {
    if (!this.hasProgressTarget) return

    // If no start time provided, don't update progress (keep backend-calculated value)
    if (!this.startTimeValue || this.startTimeValue === "") {
      return
    }

    const maxMinutes = this.thresholdsValue.max || this.maxMinutesValue
    const progressPercentage = Math.min(100, (elapsed.minutes / maxMinutes) * 100)
    this.progressTarget.style.width = `${progressPercentage}%`
  }
  
  updateState(elapsed) {
    // If no start time provided, don't update state (keep backend-calculated classes)
    if (!this.startTimeValue || this.startTimeValue === "") {
      return
    }

    const target = this.thresholdsValue.target || this.targetMinutesValue

    // Remove all timer classes
    this.element.classList.remove('wait-green', 'wait-yellow', 'wait-red', 'timer-green', 'timer-yellow', 'timer-red')

    // Determine status based on target time
    // Green: 0 to target
    // Yellow: target to 2x target
    // Red: over 2x target
    let status
    if (elapsed.minutes <= target) {
      status = 'green'
    } else if (elapsed.minutes <= (target * 2)) {
      status = 'yellow'
    } else {
      status = 'red'
    }

    // Add appropriate classes
    if (this.element.classList.contains('wait-progress')) {
      this.element.classList.add(`wait-${status}`)
    } else {
      this.element.classList.add(`timer-${status}`)
    }

    // Update progress bar classes
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove('progress-green', 'progress-yellow', 'progress-red')
      this.progressTarget.classList.add(`progress-${status}`)
    }
  }
}