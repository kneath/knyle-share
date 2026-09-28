import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status"]
  static values = { text: String }

  async copy() {
    const text = this.hasSourceTarget ? (this.sourceTarget.value ?? this.sourceTarget.textContent) : this.textValue
    try {
      await navigator.clipboard.writeText(text)
      this.statusTarget.textContent = "Copied."
    } catch {
      if (this.hasSourceTarget && this.sourceTarget.select) this.sourceTarget.select()
      this.statusTarget.textContent = "Select and copy the text above. Your browser could not copy it automatically."
    }
  }
}
