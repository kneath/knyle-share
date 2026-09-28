import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropZone", "fileInput", "fileSelected", "fileName", "fileSize", "slug", "address", "passwordGroup", "passwordInput", "uploadButton", "form", "progress", "status", "progressBar", "error", "retry", "success", "shareUrl", "secret", "secretGroup", "sharingDetails", "details", "preview", "format", "formatHint"]
  static values = { host: String, replace: Boolean }

  connect() {
    this.selectedFile = null
    this.dragCounter = 0
    this.active = false
    this.leave = event => { if (this.active) { event.preventDefault(); event.returnValue = "" } }
    window.addEventListener("beforeunload", this.leave)
    this.clearSecret = () => {
      this.password = null
      this.secretTarget.value = ""
      this.secretGroupTarget.hidden = true
      this.sharingDetailsTarget.value = this.shareUrlTarget.value
      this.passwordInputTarget.value = ""
    }
    window.addEventListener("pagehide", this.clearSecret)
    this.accessModeChanged()
    this.passwordStrategyChanged()
    this.addressChanged()
    const id = new URL(location.href).searchParams.get("upload")
    if (id && /^\d+$/.test(id)) {
      this.uploadId = id
      this.poll().catch(error => this.fail(error, true))
    }
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.leave)
    window.removeEventListener("pagehide", this.clearSecret)
    clearTimeout(this.timer)
  }

  browse(event) { event?.stopPropagation(); this.fileInputTarget.click() }
  fileChosen() { if (this.fileInputTarget.files.length) this.selectFile(this.fileInputTarget.files[0]) }
  clearFile() {
    this.selectedFile = null
    this.fileInputTarget.value = ""
    this.fileSelectedTarget.hidden = true
    this.dropZoneTarget.hidden = false
    this.uploadButtonTarget.disabled = true
  }
  selectFile(file) {
    this.selectedFile = file
    this.fileNameTarget.textContent = file.name
    this.fileSizeTarget.textContent = this.formatBytes(file.size)
    this.fileSelectedTarget.hidden = false
    this.dropZoneTarget.hidden = true
    this.uploadButtonTarget.disabled = false
    this.errorTarget.hidden = true
    if (!this.slugTarget.value) this.slugTarget.value = this.slugify(file.name)
    this.formatTarget.value = /\.(tar\.gz|tgz)$/i.test(file.name) ? "directory" : "file"
    this.formatChanged()
    this.addressChanged()
  }
  dragenter(event) { event.preventDefault(); this.dragCounter++; this.dropZoneTarget.classList.add("is-dragover") }
  dragleave(event) { event.preventDefault(); if (--this.dragCounter <= 0) this.dropZoneTarget.classList.remove("is-dragover") }
  dragover(event) { event.preventDefault() }
  drop(event) {
    event.preventDefault()
    this.dragCounter = 0
    this.dropZoneTarget.classList.remove("is-dragover")
    if (event.dataTransfer.files.length !== 1 || event.dataTransfer.items?.[0]?.webkitGetAsEntry?.()?.isDirectory) {
      this.showError("Choose one file, or package a folder as .tar.gz to share all its files.")
      return
    }
    this.selectFile(event.dataTransfer.files[0])
  }
  addressChanged() { this.addressTarget.textContent = `${location.protocol}//${this.slugTarget.value || "your-address"}.${this.hostValue}${location.port ? `:${location.port}` : ""}/` }
  accessModeChanged() { this.passwordGroupTarget.hidden = this.accessMode === "public" }
  passwordStrategyChanged() { this.passwordInputTarget.hidden = this.passwordStrategy !== "custom"; this.passwordInputTarget.required = this.accessMode === "protected" && this.passwordStrategy === "custom" }
  formatChanged() {
    this.formatHintTarget.textContent = this.formatTarget.value === "directory" ? "A .tar.gz or .tgz archive with index.html at its root becomes a website. Other folders become a browsable file collection." : "Markdown, images, audio, video, and PDFs get a preview. Other files get a download page."
  }
  get accessMode() { return this.element.querySelector('input[name="access_mode"]:checked')?.value || "protected" }
  get passwordStrategy() { return this.element.querySelector('input[name="password_strategy"]:checked')?.value || "generated" }
  get csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content || "" }
  generatedPassword() {
    const bytes = crypto.getRandomValues(new Uint8Array(16))
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }

  async upload(event) {
    event.preventDefault()
    if (this.active || !this.selectedFile) return
    this.errorTarget.hidden = true
    this.slugTarget.value = this.slugTarget.value.trim()
    if (!this.formTarget.reportValidity()) return
    if (this.formatTarget.value === "directory" && !/\.(tar\.gz|tgz)$/i.test(this.selectedFile.name)) return this.showError("Folder publishing needs a .tar.gz or .tgz archive.")
    this.canceled = false
    this.active = true
    this.uploadButtonTarget.disabled = true
    try {
      const availability = await this.request("GET", `/uploads/availability?slug=${encodeURIComponent(this.slugTarget.value)}`)
      if (!availability.valid) throw new Error("Use 1–63 lowercase letters and numbers, separated by single hyphens. This address may also be reserved.")
      if ((!this.replaceValue && availability.exists) || (this.replaceValue && !availability.exists)) throw new Error(this.replaceValue ? "This bundle no longer exists." : "That address is taken. Choose another address, or open the existing bundle and choose Replace files.")
      this.password = this.accessMode === "protected" ? (this.passwordStrategy === "custom" ? this.passwordInputTarget.value : this.passwordStrategy === "keep" ? null : this.generatedPassword()) : null
      this.showProgress("Preparing upload…")
      const data = new FormData()
      data.append("slug", this.slugTarget.value)
      data.append("source_kind", this.formatTarget.value)
      data.append("original_filename", this.selectedFile.name)
      data.append("access_mode", this.accessMode)
      data.append("replace_existing", String(this.replaceValue))
      data.append("preserve_password", String(this.passwordStrategy === "keep"))
      if (this.password) data.append("password", this.password)
      const upload = await this.request("POST", "/uploads", data)
      this.uploadId = upload.id
      const url = new URL(location.href); url.searchParams.set("upload", upload.id); history.replaceState(null, "", url)
      if (this.canceled) { await this.cancel(); return }
      this.statusTarget.textContent = "Transferring to storage…"
      try {
        await this.transfer(upload.upload_url, this.selectedFile, { "Content-Type": upload.content_type })
        await this.request("PATCH", `/uploads/${upload.id}`, JSON.stringify({byte_size:this.selectedFile.size}))
      } catch (error) {
        if (this.canceled) return
        // CORS or a direct-upload network failure can use the same staged key
        // through Rails. No duplicate upload record or new publication is made.
        this.statusTarget.textContent = "Retrying transfer through the application…"
        const fallback = new FormData(); fallback.append("file", this.selectedFile)
        await this.transfer(`/uploads/${upload.id}/file`, fallback, {"X-CSRF-Token":this.csrfToken}, "PUT")
      }
      if (!this.canceled) await this.retry()
    } catch (error) { if (!this.canceled) this.fail(error) }
  }

  async retry() {
    this.active = true
    this.canceled = false
    this.showProgress("Preparing preview… You can return to this page if you close it.")
    this.progressBarTarget.removeAttribute("value")
    try { await this.request("POST", `/uploads/${this.uploadId}/process`); await this.poll() }
    catch (error) { this.fail(error, true) }
  }
  async poll() {
    clearTimeout(this.timer)
    const upload = await this.request("GET", `/uploads/${this.uploadId}`)
    if (this.canceled) return
    if (upload.status === "ready") return this.complete(upload)
    if (["queued", "processing"].includes(upload.status)) {
      this.active = false // Files are safely staged; publication survives leaving.
      this.showProgress("Preparing preview… You can leave and return to this page.")
      this.progressBarTarget.removeAttribute("value")
      this.timer = setTimeout(() => this.poll().catch(error => this.fail(error, true)), 2000)
    } else if (["failed", "staged"].includes(upload.status)) {
      this.fail(new Error(upload.error || "Your file is uploaded. Continue preparing its preview."), true)
    } else {
      this.uploadId = null
      this.fail(new Error("The transfer did not finish. Choose the file again to restart."))
    }
  }
  async cancel() {
    this.canceled = true
    this.xhr?.abort()
    clearTimeout(this.timer)
    try {
      if (this.uploadId) {
        const result = await this.request("DELETE", `/uploads/${this.uploadId}`)
        if (result.status === "ready") { this.canceled = false; return this.complete(result) }
      }
      this.uploadId = null
      const url = new URL(location.href); url.searchParams.delete("upload"); history.replaceState(null, "", url)
      this.formTarget.hidden = false; this.progressTarget.hidden = true
      this.showError("Upload canceled. Your selected file is still available to try again.")
    } catch (error) { this.showError(`Could not confirm cancellation. ${error.message}`) }
    finally { this.active = false; this.uploadButtonTarget.disabled = !this.selectedFile }
  }
  complete(upload) {
    this.active = false
    this.formTarget.hidden = true; this.progressTarget.hidden = true; this.errorTarget.hidden = true; this.successTarget.hidden = false
    this.shareUrlTarget.value = upload.public_url || ""
    this.secretGroupTarget.hidden = !this.password
    this.secretTarget.value = this.password || ""
    this.sharingDetailsTarget.value = `${upload.public_url || ""}${this.password ? `\nPassword: ${this.password}` : ""}`
    this.detailsTarget.href = `/bundles/${upload.bundle_slug || upload.slug}`
    this.previewTarget.href = upload.public_url || this.detailsTarget.href
    this.successTarget.focus()
  }
  showProgress(message) {
    this.formTarget.hidden = true; this.progressTarget.hidden = false; this.retryTarget.hidden = true
    this.statusTarget.textContent = message; this.progressBarTarget.value = 0
  }
  fail(error, retry = false) {
    this.active = false; this.uploadButtonTarget.disabled = !this.selectedFile
    this.retryTarget.hidden = !retry
    this.formTarget.hidden = retry; this.progressTarget.hidden = !retry
    if (retry) this.statusTarget.textContent = "Your file is saved. Retry preparation without uploading it again."
    this.showError(error.message)
  }
  showError(message) { this.errorTarget.textContent = message; this.errorTarget.hidden = false; this.errorTarget.focus() }
  async request(method, url, body) {
    const headers = {"Accept":"application/json", "X-CSRF-Token":this.csrfToken}
    if (typeof body === "string") headers["Content-Type"] = "application/json"
    const response = await fetch(url, {method,headers,body,signal:AbortSignal.timeout(30000)})
    if (response.status === 401 || response.redirected) throw new Error("Your session expired. Sign in again, then return here to continue.")
    const data = await response.json().catch(() => { throw new Error("The server could not finish this request. Please retry.") })
    if (!response.ok) throw new Error(data.error || "The request failed. Please retry.")
    return data
  }
  transfer(url, body, headers, method = "PUT") {
    return new Promise((resolve,reject) => {
      const xhr = this.xhr = new XMLHttpRequest()
      xhr.open(method,url); xhr.timeout = 30 * 60 * 1000
      Object.entries(headers).forEach(([key,value]) => xhr.setRequestHeader(key,value))
      xhr.upload.onprogress = event => {
        if (!event.lengthComputable) return
        const percent = Math.round(event.loaded / event.total * 100)
        this.progressBarTarget.value = percent
        this.statusTarget.textContent = percent === 100 ? "Saving file…" : `Transferring ${percent}% · ${this.formatBytes(event.loaded)} of ${this.formatBytes(event.total)}`
      }
      xhr.onload = () => xhr.status >= 200 && xhr.status < 300 ? resolve() : reject(new Error("File transfer failed. Check your connection and retry."))
      xhr.onerror = xhr.ontimeout = () => reject(new Error("File transfer was interrupted. Check your connection and retry."))
      xhr.onabort = () => reject(new Error("Upload canceled."))
      xhr.send(body)
    })
  }
  formatBytes(bytes) { const units = ["B","KB","MB","GB"]; const power = Math.min(3, Math.floor(Math.log(Math.max(1,bytes))/Math.log(1024))); return `${(bytes / 1024 ** power).toFixed(power ? 1 : 0)} ${units[power]}` }
  slugify(name) { return name.replace(/\.(tar\.gz|tgz|[^.]+)$/i, "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g, "").slice(0,63).replace(/-+$/, "") || "shared-file" }
}
