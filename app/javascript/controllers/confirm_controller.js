import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { message: String, field: String, initial: String }
  submit(event) {
    if (this.hasFieldValue && this.element.querySelector(this.fieldValue)?.value === this.initialValue) return
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }
}
