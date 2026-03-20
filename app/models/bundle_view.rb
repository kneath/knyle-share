class BundleView < ApplicationRecord
  belongs_to :bundle
  belongs_to :viewer_session, optional: true

  validates :access_method, presence: true
  validates :request_path, presence: true
  validates :viewed_at, presence: true
end
