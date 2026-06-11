import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "frame"]

  open(event) {
    event.preventDefault()
    this.frameTarget.src = event.currentTarget.href
    this.element.dataset.state = "open"
    document.body.style.overflow = "hidden"
  }

  close(event) {
    event?.preventDefault()
    this.element.dataset.state = ""
    document.body.style.overflow = ""
    this.panelTarget.addEventListener("transitionend", () => {
      this.frameTarget.src = ""
      this.frameTarget.innerHTML = ""
    }, { once: true })
  }

  submitEnd(event) {
    if (event.detail.success) this.close()
  }

  closeOnKeydown(event) {
    if (event.key === "Escape") this.close()
  }
}
