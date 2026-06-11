import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]
  static classes = ["active"]

  connect() {
    this.#mql = window.matchMedia("(max-width: 768px)")
    this.#mqlHandler = (e) => { if (!e.matches) this.close() }
    this.#mql.addEventListener("change", this.#mqlHandler)
  }

  disconnect() {
    this.#mql?.removeEventListener("change", this.#mqlHandler)
  }

  toggle() {
    this.contentTarget.classList.toggle(this.#activeClass)
  }

  open() {
    this.contentTarget.classList.add(this.#activeClass)
  }

  close() {
    this.contentTarget.classList.remove(this.#activeClass)
  }

  get #activeClass() {
    return this.hasActiveClass ? this.activeClass : "open"
  }

  #mql
  #mqlHandler
}
