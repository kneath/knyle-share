class BindReplacementsToRevision < ActiveRecord::Migration[8.0]
  def change
    add_column :bundle_uploads, :expected_content_revision, :integer
    add_column :bundle_uploads, :expected_access_revision, :integer
  end
end
