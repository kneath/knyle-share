class ViewerSession < ApplicationRecord
  belongs_to :bundle
  has_many :bundle_views, dependent: :nullify
  has_many :bundle_unique_viewers, dependent: :destroy

  validates :access_revision, presence: true, numericality: { greater_than_or_equal_to: 1, only_integer: true }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
end
