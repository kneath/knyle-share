class CreateBundleUniqueViewers < ActiveRecord::Migration[8.0]
  def up
    create_table :bundle_unique_viewers do |t|
      t.references :bundle, null: false, foreign_key: true
      t.references :viewer_session, null: false, foreign_key: true
      t.datetime :first_viewed_at, null: false

      t.timestamps
    end

    add_index :bundle_unique_viewers, %i[bundle_id viewer_session_id], unique: true

    execute <<~SQL.squish
      INSERT INTO bundle_unique_viewers (bundle_id, viewer_session_id, first_viewed_at, created_at, updated_at)
      SELECT bundle_id, viewer_session_id, MIN(viewed_at), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM bundle_views
      WHERE viewer_session_id IS NOT NULL
      GROUP BY bundle_id, viewer_session_id
    SQL

    execute <<~SQL.squish
      UPDATE bundles
      SET unique_protected_viewers_count = (
        SELECT COUNT(*)
        FROM bundle_unique_viewers
        WHERE bundle_unique_viewers.bundle_id = bundles.id
      )
    SQL
  end

  def down
    drop_table :bundle_unique_viewers
  end
end
