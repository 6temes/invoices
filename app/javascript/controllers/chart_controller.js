import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { data: Array }

  connect() {
    this.#render()
    // A morph refresh replaces our container with the empty server-rendered
    // div, wiping the bars we drew — and connect() doesn't re-fire on morph.
    // Re-render after each morph so the chart survives page-refresh broadcasts.
    document.addEventListener("turbo:morph", this.#render)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.#render)
  }

  #render = () => {
    const data = this.dataValue
    if (!data.length) return

    const maxAmount = Math.max(...data.map(d => d.total))

    const chart = document.createElement('div')
    chart.className = 'chart'

    data.forEach(d => {
      const group = document.createElement('div')
      group.className = 'chart-bar-group'

      const bars = document.createElement('div')
      bars.className = 'chart-bars'

      const paidHeight = maxAmount > 0 ? (d.paid / maxAmount * 120) : 0
      const openHeight = maxAmount > 0 ? ((d.total - d.paid) / maxAmount * 120) : 0

      const openBar = document.createElement('div')
      openBar.className = 'chart-bar chart-bar-open'
      openBar.style.height = '0px'
      openBar.dataset.height = `${openHeight}px`
      openBar.title = `Open: ¥${(d.total - d.paid).toLocaleString()}`

      const paidBar = document.createElement('div')
      paidBar.className = 'chart-bar chart-bar-paid'
      paidBar.style.height = '0px'
      paidBar.dataset.height = `${paidHeight}px`
      paidBar.title = `Paid: ¥${d.paid.toLocaleString()}`

      bars.appendChild(openBar)
      bars.appendChild(paidBar)

      const label = document.createElement('div')
      label.className = 'chart-label'
      label.textContent = d.month

      group.appendChild(bars)
      group.appendChild(label)
      chart.appendChild(group)
    })

    this.element.replaceChildren(chart)

    requestAnimationFrame(() => {
      chart.querySelectorAll('.chart-bar').forEach((bar, i) => {
        bar.style.transitionDelay = `${i * 30}ms`
        bar.style.height = bar.dataset.height
      })
    })
  }
}
