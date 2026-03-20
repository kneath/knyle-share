class CreateInstallations < ActiveRecord::Migration[8.0]
  def change
    create_table :installations do |t|
      t.string :admin_github_uid
      t.string :admin_github_login
      t.string :admin_github_name
      t.string :admin_github_avatar_url
      t.datetime :admin_claimed_at

      t.timestamps
    end

    add_index :installations, :admin_github_uid, unique: true
  end
end
