import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "frame"]
  static values = { url: String, objectName: String, addressId: String }

  change() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("country_code", this.selectTarget.value)
    url.searchParams.set("object_name", this.objectNameValue)
    if (this.addressIdValue) url.searchParams.set("address_id", this.addressIdValue)

    this.frameTarget.src = url.toString()
  }
}
