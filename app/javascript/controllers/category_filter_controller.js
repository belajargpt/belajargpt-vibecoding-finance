import { Controller } from "@hotwired/stimulus"

// Rewrites the category <select>'s options whenever direction changes,
// so expense messages can only pick expense categories and vice versa.
// Data for the mapping is serialized into a <script type="application/json">
// inside the form (target "catalog") — no fetch, no duplication with R11.
export default class extends Controller {
  static targets = ["direction", "category", "catalog"]

  connect() {
    this.catalog = JSON.parse(this.catalogTarget.textContent)
  }

  refresh() {
    const direction = this.directionTarget.value
    const options = this.catalog[direction] || []
    const current = this.categoryTarget.value
    this.categoryTarget.innerHTML = ""
    options.forEach(label => {
      const option = document.createElement("option")
      option.value = label
      option.textContent = label
      if (label === current) option.selected = true
      this.categoryTarget.appendChild(option)
    })
    // If the old category doesn't exist in the new direction's list, fall back
    // to the first option so the field isn't blank on submit.
    if (!options.includes(current) && options.length > 0) {
      this.categoryTarget.value = options[0]
    }
  }
}
