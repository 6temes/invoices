// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Animate Turbo Stream operations with the View Transitions API
document.addEventListener("turbo:before-stream-render", (event) => {
  if (!document.startViewTransition) return

  const action = event.detail.newStream.getAttribute("action")
  if (action === "prepend" || action === "append" || action === "remove") {
    const originalRender = event.detail.render
    event.detail.render = (stream) => {
      document.startViewTransition(() => originalRender(stream))
    }
  }
})
