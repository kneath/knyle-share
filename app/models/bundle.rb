class Bundle < ApplicationRecord
  RESERVED_SLUGS = %w[api assets health rails up].freeze
  SOURCE_KIND_LABELS = {
    "directory" => "Directory",
    "file" => "File"
  }.freeze
  PRESENTATION_KIND_LABELS = {
    "file_listing" => "File Listing",
    "markdown_document" => "Markdown",
    "single_download" => "Single Download",
    "static_site" => "Static Site"
  }.freeze
  STATUS_LABELS = {
    "active" => "Active",
    "disabled" => "Disabled"
  }.freeze
  ACCESS_MODE_LABELS = {
    "protected" => "Protected",
    "public" => "Public"
  }.freeze

  has_secure_password validations: false

  has_many :assets, class_name: "BundleAsset", dependent: :destroy
  has_many :viewer_sessions, dependent: :destroy
  has_many :bundle_views, dependent: :destroy

  validates :slug,
    presence: true,
    uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :title, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KIND_LABELS.keys }
  validates :presentation_kind, inclusion: { in: PRESENTATION_KIND_LABELS.keys }
  validates :status, inclusion: { in: STATUS_LABELS.keys }
  validates :access_mode, inclusion: { in: ACCESS_MODE_LABELS.keys }
  validate :slug_is_not_reserved
  validate :protected_bundle_requires_password

  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

  def to_param
    slug
  end

  def active?
    status == "active"
  end

  def disabled?
    status == "disabled"
  end

  def public_access?
    access_mode == "public"
  end

  def protected_access?
    access_mode == "protected"
  end

  def source_label
    SOURCE_KIND_LABELS.fetch(source_kind)
  end

  def presentation_label
    PRESENTATION_KIND_LABELS.fetch(presentation_kind)
  end

  def status_label
    STATUS_LABELS.fetch(status)
  end

  def access_label
    ACCESS_MODE_LABELS.fetch(access_mode)
  end

  def status_badge_class
    active? ? "badge-active" : "badge-disabled"
  end

  def access_badge_class
    public_access? ? "badge-public" : "badge-protected"
  end

  def toggle_status!
    update!(status: active? ? "disabled" : "active")
  end

  def set_password!(new_password)
    self.password = new_password
    save!
  end

  private

  def slug_is_not_reserved
    return unless slug.present? && RESERVED_SLUGS.include?(slug)

    errors.add(:slug, "is reserved")
  end

  def protected_bundle_requires_password
    return unless protected_access? && password_digest.blank?

    errors.add(:password_digest, "must be set for protected bundles")
  end
end
