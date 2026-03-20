class AddRenderedMarkdownToBundleAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :bundle_assets, :rendered_html, :text
    add_column :bundle_assets, :rendered_html_version, :integer
  end
end
