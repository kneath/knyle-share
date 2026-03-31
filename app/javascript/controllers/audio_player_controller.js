import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["waveform", "audio", "time", "playPause"]
  static values = { url: String }

  connect() {
    this.playing = false
    this.waveformData = null
    this.animationId = null

    this.audioTarget.src = this.urlValue
    this.audioTarget.addEventListener("loadedmetadata", () => this.updateTime())
    this.audioTarget.addEventListener("timeupdate", () => this.updateTime())
    this.audioTarget.addEventListener("ended", () => this.handleEnded())

    this.resizeObserver = new ResizeObserver(() => this.drawWaveform())
    this.resizeObserver.observe(this.waveformTarget)

    this.loadWaveform()
  }

  disconnect() {
    if (this.animationId) cancelAnimationFrame(this.animationId)
    if (this.resizeObserver) this.resizeObserver.disconnect()
  }

  // ── Playback ─────────────────────────────────────────────────

  toggle() {
    if (this.playing) {
      this.audioTarget.pause()
      this.playing = false
      this.playPauseTarget.textContent = "Play"
      if (this.animationId) cancelAnimationFrame(this.animationId)
    } else {
      this.audioTarget.play()
      this.playing = true
      this.playPauseTarget.textContent = "Pause"
      this.animate()
    }
  }

  seek(event) {
    if (!this.audioTarget.duration) return

    const canvas = this.waveformTarget
    const rect = canvas.getBoundingClientRect()
    const x = event.clientX - rect.left
    const ratio = x / rect.width

    this.audioTarget.currentTime = ratio * this.audioTarget.duration
    this.drawWaveform()
  }

  handleEnded() {
    this.playing = false
    this.playPauseTarget.textContent = "Play"
    if (this.animationId) cancelAnimationFrame(this.animationId)
    this.drawWaveform()
  }

  // ── Time display ─────────────────────────────────────────────

  updateTime() {
    const current = this.formatTime(this.audioTarget.currentTime)
    const total = this.formatTime(this.audioTarget.duration || 0)
    this.timeTarget.textContent = `${current} / ${total}`
  }

  formatTime(seconds) {
    if (!isFinite(seconds)) return "0:00"
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  }

  // ── Waveform ─────────────────────────────────────────────────

  async loadWaveform() {
    try {
      const response = await fetch(this.urlValue)
      const buffer = await response.arrayBuffer()
      const audioContext = new (window.AudioContext || window.webkitAudioContext)()
      const audioBuffer = await audioContext.decodeAudioData(buffer)

      this.waveformData = this.extractWaveform(audioBuffer, 200)
      this.drawWaveform()
      audioContext.close()
    } catch (e) {
      // If waveform extraction fails, draw a flat line
      this.waveformData = new Array(200).fill(0.05)
      this.drawWaveform()
    }
  }

  extractWaveform(audioBuffer, bars) {
    const channel = audioBuffer.getChannelData(0)
    const samplesPerBar = Math.floor(channel.length / bars)
    const waveform = []

    for (let i = 0; i < bars; i++) {
      let sum = 0
      const start = i * samplesPerBar
      for (let j = start; j < start + samplesPerBar; j++) {
        sum += Math.abs(channel[j])
      }
      waveform.push(sum / samplesPerBar)
    }

    // Normalize to 0..1
    const max = Math.max(...waveform, 0.01)
    return waveform.map(v => v / max)
  }

  drawWaveform() {
    if (!this.waveformData) return

    const canvas = this.waveformTarget
    const dpr = window.devicePixelRatio || 1
    const rect = canvas.getBoundingClientRect()

    canvas.width = rect.width * dpr
    canvas.height = rect.height * dpr

    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)

    const width = rect.width
    const height = rect.height
    const bars = this.waveformData.length
    const barWidth = width / bars
    const gap = Math.max(1, barWidth * 0.2)
    const progress = this.audioTarget.duration
      ? this.audioTarget.currentTime / this.audioTarget.duration
      : 0

    ctx.clearRect(0, 0, width, height)

    const style = getComputedStyle(document.documentElement)
    const playedColor = style.getPropertyValue("--color-accent").trim() || "#2563eb"
    const unplayedColor = style.getPropertyValue("--color-border").trim() || "#e5e5e5"

    for (let i = 0; i < bars; i++) {
      const x = i * barWidth
      const barH = Math.max(2, this.waveformData[i] * height * 0.9)
      const y = (height - barH) / 2

      ctx.fillStyle = (i / bars) < progress ? playedColor : unplayedColor
      ctx.beginPath()
      ctx.roundRect(x + gap / 2, y, barWidth - gap, barH, 2)
      ctx.fill()
    }
  }

  animate() {
    if (!this.playing) return
    this.drawWaveform()
    this.animationId = requestAnimationFrame(() => this.animate())
  }
}
