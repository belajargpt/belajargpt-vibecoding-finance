import { Controller } from "@hotwired/stimulus"

// Clears the chat input after a successful submit and keeps focus so the
// owner can type the next message without tapping back in.
export default class extends Controller {
  static targets = ["input"]

  reset(event) {
    if (event.detail?.success) {
      this.inputTarget.value = ""
      this.inputTarget.focus()
    }
  }
}
