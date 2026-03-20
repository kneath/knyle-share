class ViewerSession < ApplicationRecord
  belongs_to :bundle
  has_many :bundle_views, dependent: :nullify

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
end
