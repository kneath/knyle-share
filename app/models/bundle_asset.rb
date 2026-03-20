class BundleAsset < ApplicationRecord
  belongs_to :bundle, counter_cache: :asset_count

  validates :path, presence: true, uniqueness: { scope: :bundle_id }
  validates :storage_key, presence: true
  validates :content_type, presence: true

  def has_prerendered_markdown?
    rendered_html.present? && rendered_html_version.present?
  end
end
