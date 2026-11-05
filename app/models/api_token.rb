require "digest"
require "securerandom"

class ApiToken < ApplicationRecord
  TOKEN_LENGTH = 40
  SLUG_PREFIX_FORMAT = /\A(?:[a-z0-9]+-)+\z/.freeze

  normalizes :slug_prefix, with: ->(value) { value.strip.presence }

  validates :label, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :slug_prefix,
    length: { maximum: 62 },
    format: {
      with: SLUG_PREFIX_FORMAT,
      message: "must be lowercase letters, numbers, and hyphens, ending in a hyphen (like kb-)"
    },
    allow_nil: true

  scope :active, -> { where(revoked_at: nil) }

  def self.issue!(label:, slug_prefix: nil)
    plaintext_token = SecureRandom.alphanumeric(TOKEN_LENGTH)
    record = create!(label:, slug_prefix:, token_digest: digest(plaintext_token))

    [record, plaintext_token]
  end

  def self.authenticate(plaintext_token)
    return if plaintext_token.blank?

    active.find_by(token_digest: digest(plaintext_token))
  end

  def self.digest(plaintext_token)
    Digest::SHA256.hexdigest(plaintext_token)
  end

  def active?
    revoked_at.blank?
  end

  def slug_scoped?
    slug_prefix.present?
  end

  # A token without a prefix can act on every bundle.
  def permits_slug?(slug)
    return true unless slug_scoped?

    slug.to_s.start_with?(slug_prefix)
  end

  # Narrows a relation with a slug column to the rows this token may act on.
  def permitted(relation)
    return relation unless slug_scoped?

    column = "#{relation.connection.quote_table_name(relation.table_name)}.#{relation.connection.quote_column_name("slug")}"
    relation.where("#{column} LIKE ? ESCAPE '\\'", "#{relation.sanitize_sql_like(slug_prefix)}%")
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
