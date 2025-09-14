import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate(event) {
    const path = event.target.value
    if (path) {
      window.location.href = path
    }
  }
}