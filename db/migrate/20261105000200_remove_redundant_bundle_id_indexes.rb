# Both are covered by the leading column of a composite unique index
# (bundle_id + path, bundle_id + viewer_session_id), so they only cost an
# extra write on every asset insert and every view.
class RemoveRedundantBundleIdIndexes < ActiveRecord::Migration[8.0]
  def change
    remove_index :bundle_assets, :bundle_id, name: "index_bundle_assets_on_bundle_id"
    remove_index :bundle_unique_viewers, :bundle_id, name: "index_bundle_unique_viewers_on_bundle_id"
  end
end
