import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "template", "item", "destroyField", "subtotal", "taxAmount", "total"]

  itemTargetConnected() {
    this.#recalculate()
  }

  itemTargetDisconnected() {
    this.#recalculate()
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_INDEX/g, Date.now())
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    const item = event.target.closest("[data-line-items-target='item']")
    const destroyField = item.querySelector("[data-line-items-target='destroyField']")

    if (destroyField) {
      destroyField.value = "1"
      item.style.display = "none"
      this.#recalculate()
    } else {
      item.remove()
    }
  }

  recalculate() {
    this.#recalculate()
  }

  #recalculate() {
    if (!this.hasSubtotalTarget) return

    let subtotal = 0
    this.itemTargets.forEach(item => {
      if (item.style.display === "none") return
      const qty = parseFloat(item.querySelector("[name*='quantity']")?.value) || 0
      const price = parseFloat(item.querySelector("[name*='unit_price']")?.value) || 0
      subtotal += qty * price
    })

    const taxRate = parseFloat(this.element.querySelector("[name*='tax_rate']")?.value) || 0
    const taxAmount = Math.floor(subtotal * taxRate / 100)
    const total = subtotal + taxAmount

    this.subtotalTarget.textContent = `¥${subtotal.toLocaleString()}`
    this.taxAmountTarget.textContent = `¥${taxAmount.toLocaleString()}`
    this.totalTarget.textContent = `¥${total.toLocaleString()}`
  }
}
