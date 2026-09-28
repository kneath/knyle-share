class ImprovePublishingWorkflows < ActiveRecord::Migration[8.0]
  def change
    add_column :bundles, :description, :text
    add_column :bundles, :archive_storage_key, :string
    add_column :bundles, :archive_byte_size, :bigint
    add_column :bundle_uploads, :published_bundle_id, :integer
    add_column :bundle_uploads, :processing_token, :string
    add_column :bundle_uploads, :processing_started_at, :datetime
    add_column :bundle_uploads, :publish_prefix, :string
    create_table :storage_cleanups do |t|
      t.text :object_keys, null: false
      t.string :label, null: false
      t.integer :attempts, default: 0, null: false
      t.text :last_error
      t.datetime :next_attempt_at
      t.datetime :locked_at
      t.timestamps
    end
    add_index :storage_cleanups, :next_attempt_at
  end
end
