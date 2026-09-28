import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["button", "status"]
  start() { this.buttonTarget.disabled = true; this.statusTarget.textContent = "Checking configuration…" }
}
