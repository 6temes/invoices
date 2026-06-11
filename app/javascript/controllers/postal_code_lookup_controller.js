import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "administrativeArea", "locality", "sublocality"]
  static values = { url: String }

  #controller = null
  #debounceTimer = null

  disconnect() {
    clearTimeout(this.#debounceTimer)
    this.#controller?.abort()
  }

  lookup() {
    clearTimeout(this.#debounceTimer)
    this.#debounceTimer = setTimeout(() => this.#perform(), 300)
  }

  #perform() {
    const raw = this.inputTarget.value.replace(/-/g, "")
    if (raw.length !== 7 || !/^\d{7}$/.test(raw)) return

    this.#controller?.abort()
    this.#controller = new AbortController()
    this.#setLoading(true)

    fetch(`${this.urlValue}?postal_code=${encodeURIComponent(this.inputTarget.value)}`, {
      signal: this.#controller.signal
    })
      .then(response => {
        if (!response.ok) return
        return response.json()
      })
      .then(data => {
        if (!data) return
        if (data.administrative_area) this.administrativeAreaTarget.value = data.administrative_area
        if (data.locality) this.localityTarget.value = data.locality
        if (data.sublocality) this.sublocalityTarget.value = data.sublocality
      })
      .catch(error => {
        if (error.name !== "AbortError") console.warn("Postal code lookup failed:", error)
      })
      .finally(() => this.#setLoading(false))
  }

  #setLoading(flag) {
    this.element.classList.toggle("is-loading", flag)
  }
}
