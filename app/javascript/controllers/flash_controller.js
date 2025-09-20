import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    timeout: Number
  }

  connect() {
    if (this.hasTimeoutValue && this.timeoutValue > 0) {
      this.timeoutId = window.setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  disconnect() {
    if (this.timeoutId) {
      window.clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
  }

  dismiss(event) {
    if (event) {
      event.preventDefault()
    }

    if (this.timeoutId) {
      window.clearTimeout(this.timeoutId)
      this.timeoutId = null
    }

    this.element.classList.add("flash-message--hidden")
    window.setTimeout(() => {
      this.element.remove()
    }, 200)
  }
}
