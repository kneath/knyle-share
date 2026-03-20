class AddAccessRevisionToBundlesAndViewerSessions < ActiveRecord::Migration[8.0]
  def up
    add_column :bundles, :access_revision, :integer, default: 1, null: false
    add_column :viewer_sessions, :access_revision, :integer, default: 1, null: false

    execute <<~SQL.squish
      UPDATE viewer_sessions
      SET access_revision = COALESCE(
        (
          SELECT bundles.access_revision
          FROM bundles
          WHERE bundles.id = viewer_sessions.bundle_id
        ),
        1
      )
    SQL
  end

  def down
    remove_column :viewer_sessions, :access_revision
    remove_column :bundles, :access_revision
  end
end
