import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    url: String,
    status: String,
    interval: { type: Number, default: 2000 }
  }

  connect() {
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  async refresh() {
    let shouldContinue = true

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        cache: "no-store"
      })

      if (response.ok) {
        const { status } = await response.json()
        if (status !== this.statusValue) {
          shouldContinue = false
          Turbo.visit(window.location.href, { action: "replace" })
        }
      }
    } catch (_error) {
      // A temporary network failure should not stop future status checks.
    } finally {
      if (shouldContinue) this.schedule()
    }
  }

  schedule() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.refresh(), this.intervalValue)
  }
}
