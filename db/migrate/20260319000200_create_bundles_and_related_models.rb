class CreateBundlesAndRelatedModels < ActiveRecord::Migration[8.0]
  def change
    create_table :bundles do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.string :source_kind, null: false
      t.string :presentation_kind, null: false
      t.string :status, null: false, default: "active"
      t.string :access_mode, null: false, default: "public"
      t.string :password_digest
      t.integer :password_session_ttl_seconds, null: false, default: 86_400
      t.string :entry_path
      t.bigint :byte_size, null: false, default: 0
      t.integer :asset_count, null: false, default: 0
      t.integer :content_revision, null: false, default: 1
      t.datetime :last_viewed_at
      t.datetime :last_replaced_at
      t.integer :total_views_count, null: false, default: 0
      t.integer :unique_protected_viewers_count, null: false, default: 0
      t.timestamps
    end

    add_index :bundles, :slug, unique: true

    create_table :bundle_assets do |t|
      t.references :bundle, null: false, foreign_key: true
      t.string :path, null: false
      t.string :storage_key, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false, default: 0
      t.string :checksum
      t.timestamps
    end

    add_index :bundle_assets, [:bundle_id, :path], unique: true

    create_table :viewer_sessions do |t|
      t.references :bundle, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :viewer_sessions, :token_digest, unique: true

    create_table :bundle_views do |t|
      t.references :bundle, null: false, foreign_key: true
      t.references :viewer_session, foreign_key: true
      t.string :access_method, null: false
      t.string :request_path, null: false
      t.datetime :viewed_at, null: false
      t.timestamps
    end

    add_index :bundle_views, :viewed_at
  end
end
