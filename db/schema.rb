# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_03_20_000100) do
  create_table "api_tokens", force: :cascade do |t|
    t.string "label", null: false
    t.string "token_digest", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
  end

  create_table "bundle_assets", force: :cascade do |t|
    t.integer "bundle_id", null: false
    t.string "path", null: false
    t.string "storage_key", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", default: 0, null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id", "path"], name: "index_bundle_assets_on_bundle_id_and_path", unique: true
    t.index ["bundle_id"], name: "index_bundle_assets_on_bundle_id"
  end

  create_table "bundle_uploads", force: :cascade do |t|
    t.string "slug", null: false
    t.string "source_kind", null: false
    t.string "original_filename"
    t.string "access_mode", null: false
    t.string "password_digest"
    t.boolean "replace_existing", default: false, null: false
    t.string "ingest_key", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.bigint "byte_size", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_bundle_uploads_on_slug"
    t.index ["status"], name: "index_bundle_uploads_on_status"
  end

  create_table "bundle_views", force: :cascade do |t|
    t.integer "bundle_id", null: false
    t.integer "viewer_session_id"
    t.string "access_method", null: false
    t.string "request_path", null: false
    t.datetime "viewed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_bundle_views_on_bundle_id"
    t.index ["viewed_at"], name: "index_bundle_views_on_viewed_at"
    t.index ["viewer_session_id"], name: "index_bundle_views_on_viewer_session_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.string "source_kind", null: false
    t.string "presentation_kind", null: false
    t.string "status", default: "active", null: false
    t.string "access_mode", default: "public", null: false
    t.string "password_digest"
    t.integer "password_session_ttl_seconds", default: 86400, null: false
    t.string "entry_path"
    t.bigint "byte_size", default: 0, null: false
    t.integer "asset_count", default: 0, null: false
    t.integer "content_revision", default: 1, null: false
    t.datetime "last_viewed_at"
    t.datetime "last_replaced_at"
    t.integer "total_views_count", default: 0, null: false
    t.integer "unique_protected_viewers_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "access_revision", default: 1, null: false
    t.index ["slug"], name: "index_bundles_on_slug", unique: true
  end

  create_table "installations", force: :cascade do |t|
    t.string "admin_github_uid"
    t.string "admin_github_login"
    t.string "admin_github_name"
    t.string "admin_github_avatar_url"
    t.datetime "admin_claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_github_uid"], name: "index_installations_on_admin_github_uid", unique: true
  end

  create_table "viewer_sessions", force: :cascade do |t|
    t.integer "bundle_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "access_revision", default: 1, null: false
    t.index ["bundle_id"], name: "index_viewer_sessions_on_bundle_id"
    t.index ["token_digest"], name: "index_viewer_sessions_on_token_digest", unique: true
  end

  add_foreign_key "bundle_assets", "bundles"
  add_foreign_key "bundle_views", "bundles"
  add_foreign_key "bundle_views", "viewer_sessions"
  add_foreign_key "viewer_sessions", "bundles"
end
