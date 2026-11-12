class ServeSingleHtmlBundlesAsSites < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE bundles
      SET presentation_kind = 'static_site'
      WHERE presentation_kind = 'single_download'
        AND source_kind = 'file'
        AND (lower(entry_path) LIKE '%.html' OR lower(entry_path) LIKE '%.htm')
    SQL
  end

  def down
    execute <<~SQL
      UPDATE bundles
      SET presentation_kind = 'single_download'
      WHERE presentation_kind = 'static_site'
        AND source_kind = 'file'
    SQL
  end
end
