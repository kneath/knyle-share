class IndexViewerSessionsOnExpiresAt < ActiveRecord::Migration[8.0]
  def change
    add_index :viewer_sessions, :expires_at
  end
end
