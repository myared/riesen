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
    
    const maxMinutes = this.thresholdsValue.max || this.maxMinutesValue
    const progressPercentage = Math.min(100, (elapsed.minutes / maxMinutes) * 100)
    this.progressTarget.style.width = `${progressPercentage}%`
  }
  
  updateState(elapsed) {
    const warning = this.thresholdsValue.warning || this.constructor.DEFAULTS.WARNING_THRESHOLD
    const critical = this.thresholdsValue.critical || this.constructor.DEFAULTS.CRITICAL_THRESHOLD
    
    // Remove all timing classes
    this.element.classList.remove('timing-normal', 'timing-warning', 'timing-critical')
    
    // For progress-based coloring (using target minutes)
    if (this.thresholdsValue.useTarget || this.targetMinutesValue < 60) {
      const percentage = (elapsed.minutes / this.targetMinutesValue) * 100
      
      if (percentage >= 100) {
        this.element.classList.add('timing-critical')
      } else if (percentage >= 80) {
        this.element.classList.add('timing-warning')
      } else {
        this.element.classList.add('timing-normal')
      }
    } else {
      // For time-based coloring (fixed thresholds)
      if (elapsed.minutes >= critical) {
        this.element.classList.add('timing-critical')
      } else if (elapsed.minutes >= warning) {
        this.element.classList.add('timing-warning')
      } else {
        this.element.classList.add('timing-normal')
      }
    }
    
    // Update progress bar classes
    if (this.hasProgressTarget) {
      this.progressTarget.classList.remove('progress-normal', 'progress-warning', 'progress-critical')
      
      const currentClass = Array.from(this.element.classList).find(c => c.startsWith('timing-'))
      if (currentClass) {
        const state = currentClass.replace('timing-', '')
        this.progressTarget.classList.add(`progress-${state}`)
      }
    }
  }
}