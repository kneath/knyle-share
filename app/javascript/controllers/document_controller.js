import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  connect() {
    this.element.querySelectorAll(".markdown-body table").forEach(table => {
      const wrapper = document.createElement("div")
      wrapper.className = "table-scroll"; wrapper.tabIndex = 0; wrapper.setAttribute("role", "region"); wrapper.setAttribute("aria-label", "Scrollable table")
      table.before(wrapper); wrapper.append(table)
    })
    this.element.querySelectorAll(".markdown-body pre").forEach(pre => {
      const button = document.createElement("button")
      button.className = "btn btn-secondary code-copy"; button.type = "button"; button.textContent = "Copy code"
      button.addEventListener("click", async () => {
        try { await navigator.clipboard.writeText(pre.textContent); button.textContent = "Copied" }
        catch { button.textContent = "Select code to copy" }
      })
      pre.before(button)
    })
  }
  toggleFont(event) {
    const reading = this.element.classList.toggle("reading-font")
    event.currentTarget.setAttribute("aria-pressed", String(reading))
    event.currentTarget.textContent = reading ? "Monospace font" : "Reading font"
  }
}
