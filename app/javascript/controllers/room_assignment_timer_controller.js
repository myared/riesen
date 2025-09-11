import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["timer", "progress"]
  static values = { 
    startTime: String,
    maxMinutes: { type: Number, default: 20 }
  }
  
  connect() {
    this.updateTimer()
    this.startTimer()
  }
  
  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }
  
  startTimer() {
    this.timer = setInterval(() => {
      this.updateTimer()
    }, 1000)
  }
  
  updateTimer() {
    const startTime = new Date(this.startTimeValue)
    const now = new Date()
    const elapsedMs = now - startTime
    const elapsedMinutes = Math.floor(elapsedMs / 60000)
    const elapsedSeconds = Math.floor((elapsedMs % 60000) / 1000)
    
    const remainingMinutes = Math.max(0, this.maxMinutesValue - elapsedMinutes)
    const displayMinutes = Math.min(elapsedMinutes, this.maxMinutesValue)
    const displaySeconds = elapsedMinutes >= this.maxMinutesValue ? 0 : elapsedSeconds
    
    // Update timer display
    if (this.hasTimerTarget) {
      if (remainingMinutes > 0 || displaySeconds > 0) {
        this.timerTarget.textContent = `${String(remainingMinutes).padStart(2, '0')}:${String(59 - displaySeconds).padStart(2, '0')}`
        this.timerTarget.classList.remove('timer-expired')
        this.timerTarget.classList.add('timer-active')
      } else {
        this.timerTarget.textContent = '00:00'
        this.timerTarget.classList.remove('timer-active')
        this.timerTarget.classList.add('timer-expired')
      }
    }
    
    // Update progress bar
    if (this.hasProgressTarget) {
      const progressPercentage = Math.min(100, (elapsedMinutes / this.maxMinutesValue) * 100)
      this.progressTarget.style.width = `${progressPercentage}%`
      
      // Change color based on time remaining
      if (remainingMinutes <= 5) {
        this.progressTarget.classList.add('progress-warning')
      }
      if (remainingMinutes <= 0) {
        this.progressTarget.classList.add('progress-expired')
      }
    }
  }
}