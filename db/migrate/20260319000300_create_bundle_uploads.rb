class CreateBundleUploads < ActiveRecord::Migration[8.0]
  def change
    create_table :bundle_uploads do |t|
      t.string :slug, null: false
      t.string :source_kind, null: false
      t.string :original_filename
      t.string :access_mode, null: false
      t.string :password_digest
      t.boolean :replace_existing, null: false, default: false
      t.string :ingest_key, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.bigint :byte_size, null: false, default: 0
      t.timestamps
    end

    add_index :bundle_uploads, :slug
    add_index :bundle_uploads, :status
  end
end
