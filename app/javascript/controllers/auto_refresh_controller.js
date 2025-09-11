import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    interval: { type: Number, default: 60000 }
  }

  connect() {
    this.refresh()
    this.startRefreshing()
  }

  disconnect() {
    this.stopRefreshing()
  }

  startRefreshing() {
    this.refreshTimer = setInterval(() => {
      this.refresh()
    }, this.intervalValue)
  }

  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  refresh() {
    fetch(window.location.href, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.text())
    .then(html => {
      const parser = new DOMParser()
      const newDocument = parser.parseFromString(html, "text/html")
      
      const currentMain = document.querySelector('.dashboard-main')
      const newMain = newDocument.querySelector('.dashboard-main')
      
      const currentSidebar = document.querySelector('.dashboard-sidebar')
      const newSidebar = newDocument.querySelector('.dashboard-sidebar')
      
      if (currentMain && newMain) {
        currentMain.innerHTML = newMain.innerHTML
      }
      
      if (currentSidebar && newSidebar) {
        currentSidebar.innerHTML = newSidebar.innerHTML
      }
    })
    .catch(error => {
      console.error("Auto-refresh error:", error)
    })
  }
}