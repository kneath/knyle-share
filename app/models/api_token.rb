require "digest"
require "securerandom"

class ApiToken < ApplicationRecord
  TOKEN_LENGTH = 40

  validates :label, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  def self.issue!(label:)
    plaintext_token = SecureRandom.alphanumeric(TOKEN_LENGTH)
    record = create!(label:, token_digest: digest(plaintext_token))

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

  def revoke!
    update!(revoked_at: Time.current)
  end
end
