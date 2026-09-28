import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["viewport", "button"]
  toggle() {
    const actual = this.viewportTarget.classList.toggle("is-actual-size")
    this.buttonTarget.textContent = actual ? "Fit to screen" : "Actual size"
    this.buttonTarget.setAttribute("aria-pressed", String(actual))
  }
}
