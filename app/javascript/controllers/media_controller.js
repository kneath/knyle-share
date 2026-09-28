import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["media", "status", "retry"]
  static values = { source: String }
  connect() { this.refreshed = false }
  waiting() { this.statusTarget.textContent = "Loading media…" }
  ready() { this.statusTarget.textContent = ""; this.retryTarget.hidden = true }
  failed() {
    this.statusTarget.textContent = navigator.onLine ? "The preview could not load. Retry it or download the file." : "You appear to be offline. Reconnect, then retry."
    this.retryTarget.hidden = false
    if (!this.refreshed && navigator.onLine) this.refresh()
  }
  async refresh() {
    this.refreshed = true
    const media = this.mediaTarget
    const position = media.currentTime || 0
    const playing = "paused" in media && !media.paused
    this.waiting()
    try {
      const response = await fetch(this.sourceValue, {headers:{Accept:"application/json"}, cache:"no-store"})
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || "Please reopen the shared link to continue.")
      if ("currentTime" in media) {
        media.addEventListener("loadedmetadata", () => {
          media.currentTime = Math.min(position, Number.isFinite(media.duration) ? media.duration : position)
          if (playing) media.play().catch(() => { this.statusTarget.textContent = "Press Play to continue." })
        }, {once:true})
      }
      media.src = result.url
      media.load?.()
    } catch (error) { this.statusTarget.textContent = error.message; this.retryTarget.hidden = false }
  }
  speed(event) { this.mediaTarget.playbackRate = Number(event.target.value) }
}
