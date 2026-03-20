class BundleUpload < ApplicationRecord
  RESERVED_SLUGS = %w[api assets health rails up].freeze
  SOURCE_KIND_VALUES = %w[directory file].freeze
  ACCESS_MODE_VALUES = %w[public protected].freeze
  STATUS_VALUES = %w[pending staged processing ready failed].freeze

  has_secure_password validations: false

  validates :slug,
    presence: true,
    uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :source_kind, inclusion: { in: SOURCE_KIND_VALUES }
  validates :access_mode, inclusion: { in: ACCESS_MODE_VALUES }
  validates :status, inclusion: { in: STATUS_VALUES }
  validates :original_filename, presence: true
  validates :ingest_key, presence: true
  validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
  validates :replace_existing, inclusion: { in: [true, false] }
  validate :slug_is_not_reserved
  validate :protected_upload_requires_password

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def pending?
    status == "pending"
  end

  def staged?
    status == "staged"
  end

  def processing?
    status == "processing"
  end

  def ready?
    status == "ready"
  end

  def failed?
    status == "failed"
  end

  def public_access?
    access_mode == "public"
  end

  def protected_access?
    access_mode == "protected"
  end

  def mark_staged!
    update!(status: "staged")
  end

  def mark_processing!
    update!(status: "processing")
  end

  def mark_ready!
    update!(status: "ready", error_message: nil)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  private

  def slug_is_not_reserved
    return unless slug.present? && RESERVED_SLUGS.include?(slug)

    errors.add(:slug, "is reserved")
  end

  def protected_upload_requires_password
    return unless protected_access? && password_digest.blank?

    errors.add(:password_digest, "must be set for protected uploads")
  end
end
