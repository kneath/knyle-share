class BundleUniqueViewer < ApplicationRecord
  belongs_to :bundle
  belongs_to :viewer_session

  validates :first_viewed_at, presence: true
  validates :viewer_session_id, uniqueness: { scope: :bundle_id }
end
