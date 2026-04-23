import { Controller } from "@hotwired/stimulus"

// Keeps the chat scrolled to the newest message. Runs on initial load and
// whenever a Turbo Stream mutates the list (render / broadcast arrivals).
export default class extends Controller {
  static targets = ["stream"]

  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.streamTarget, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.streamTarget.scrollTop = this.streamTarget.scrollHeight
  }
}
