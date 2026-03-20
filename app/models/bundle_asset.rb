class BundleAsset < ApplicationRecord
  belongs_to :bundle, counter_cache: :asset_count

  validates :path, presence: true, uniqueness: { scope: :bundle_id }
  validates :storage_key, presence: true
  validates :content_type, presence: true
end
