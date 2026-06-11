import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  #timeout = null

  connect() {
    this.element.dataset.state = 'entering'
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.element.dataset.state = 'visible'
      })
    })
    this.#timeout = setTimeout(() => this.#remove(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.#timeout)
  }

  dismiss() {
    this.#remove()
  }

  #remove() {
    clearTimeout(this.#timeout)
    this.element.dataset.state = 'leaving'
    this.element.addEventListener('transitionend', () => this.element.remove(), { once: true })
  }
}
