import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dropZone", "fileInput", "fileSelected", "fileName", "fileSize",
    "slug", "passwordGroup", "passwordInput", "uploadButton",
    "form", "progress", "status", "progressBar", "error"
  ]

  connect() {
    this.selectedFile = null
    this.dragCounter = 0
  }

  // ── File selection ────────────────────────────────────────────

  browse() {
    this.fileInputTarget.click()
  }

  fileChosen() {
    if (this.fileInputTarget.files.length > 0) {
      this.selectFile(this.fileInputTarget.files[0])
    }
  }

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
    this.clearError()

    if (!this.slugTarget.value) {
      this.slugTarget.value = this.slugify(file.name)
    }
  }

  // ── Drag and drop ─────────────────────────────────────────────

  dragenter(event) {
    event.preventDefault()
    this.dragCounter++
    this.dropZoneTarget.classList.add("is-dragover")
  }

  dragleave(event) {
    event.preventDefault()
    this.dragCounter--
    if (this.dragCounter === 0) {
      this.dropZoneTarget.classList.remove("is-dragover")
    }
  }

  dragover(event) {
    event.preventDefault()
  }

  drop(event) {
    event.preventDefault()
    this.dragCounter = 0
    this.dropZoneTarget.classList.remove("is-dragover")

    if (event.dataTransfer.files.length > 0) {
      this.selectFile(event.dataTransfer.files[0])
    }
  }

  // ── Access mode toggle ────────────────────────────────────────

  accessModeChanged(event) {
    this.updatePillSelection(event.target)
    this.passwordGroupTarget.hidden = this.accessMode === "public"
  }

  passwordStrategyChanged(event) {
    this.updatePillSelection(event.target)
    this.passwordInputTarget.hidden = this.passwordStrategy !== "custom"
  }

  updatePillSelection(radio) {
    const group = radio.closest(".pill-group")
    group.querySelectorAll(".pill").forEach((pill) => {
      pill.classList.toggle("is-selected", pill.contains(pill.querySelector("input:checked")))
    })
  }

  // ── Upload ────────────────────────────────────────────────────

  async upload() {
    this.clearError()
    if (!this.selectedFile) return

    const slug = this.slugTarget.value.trim() || this.slugify(this.selectedFile.name)
    const password = this.resolvePassword()

    if (this.accessMode === "protected" && this.passwordStrategy === "custom" && !password) {
      this.showError("Enter a password or switch to generated.")
      return
    }

    this.formTarget.hidden = true
    this.progressTarget.hidden = false
    this.statusTarget.textContent = "Uploading\u2026"
    this.progressBarTarget.style.width = "0%"

    try {
      // Step 1: Upload file through Rails to S3
      const formData = new FormData()
      formData.append("file", this.selectedFile)
      formData.append("slug", slug)
      formData.append("source_kind", "file")
      formData.append("original_filename", this.selectedFile.name)
      formData.append("access_mode", this.accessMode)
      formData.append("replace_existing", "false")
      if (password) formData.append("password", password)

      const uploadResult = await this.uploadWithProgress("/uploads", formData)

      // Step 2: Process the upload into a bundle
      this.statusTarget.textContent = "Processing\u2026"
      this.progressBarTarget.style.width = "100%"
      const result = await this.jsonRequest("POST", `/uploads/${uploadResult.id}/process`)

      window.location.href = `/bundles/${result.bundle_slug}`
    } catch (err) {
      this.progressTarget.hidden = true
      this.formTarget.hidden = false
      this.showError(err.message)
    }
  }

  // ── Private helpers ───────────────────────────────────────────

  get accessMode() {
    const checked = this.element.querySelector('input[name="access_mode"]:checked')
    return checked ? checked.value : "protected"
  }

  get passwordStrategy() {
    const checked = this.element.querySelector('input[name="password_strategy"]:checked')
    return checked ? checked.value : "generated"
  }

  resolvePassword() {
    if (this.accessMode === "public") return undefined
    if (this.passwordStrategy === "custom") return this.passwordInputTarget.value

    const words = [
      "amber", "breeze", "cedar", "dusk", "ember", "frost", "grove", "haze",
      "iris", "jade", "knoll", "lark", "marsh", "north", "opal", "pine",
      "quill", "ridge", "stone", "tide", "vale", "willow", "yarrow", "zephyr"
    ]
    const picked = []
    for (let i = 0; i < 3; i++) {
      picked.push(words[Math.floor(Math.random() * words.length)])
    }
    return picked.join(" ")
  }

  get csrfToken() {
    const tag = document.querySelector('meta[name="csrf-token"]')
    return tag ? tag.getAttribute("content") : ""
  }

  uploadWithProgress(url, formData) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open("POST", url)
      xhr.setRequestHeader("X-CSRF-Token", this.csrfToken)
      xhr.setRequestHeader("Accept", "application/json")

      xhr.upload.addEventListener("progress", (e) => {
        if (e.lengthComputable) {
          this.progressBarTarget.style.width = `${Math.round((e.loaded / e.total) * 100)}%`
        }
      })

      xhr.addEventListener("load", () => {
        try {
          const data = JSON.parse(xhr.responseText)
          if (xhr.status >= 200 && xhr.status < 300) resolve(data)
          else reject(new Error(data.error || "Upload failed"))
        } catch {
          reject(new Error("Upload failed"))
        }
      })

      xhr.addEventListener("error", () => reject(new Error("Upload failed")))
      xhr.send(formData)
    })
  }

  async jsonRequest(method, url) {
    const response = await fetch(url, {
      method,
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Accept": "application/json"
      }
    })

    const data = await response.json()
    if (!response.ok) throw new Error(data.error || "Request failed")
    return data
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  slugify(name) {
    const stem = name.replace(/\.(tar\.gz|tgz)$/i, "").replace(/\.[^.]+$/, "")
    return stem
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .replace(/-{2,}/g, "-")
  }
}
