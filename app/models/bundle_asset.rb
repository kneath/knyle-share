class BundleAsset < ApplicationRecord
  FileListingEntry = Struct.new(:path, :name, :directory, :byte_size, keyword_init: true) do
    def directory?
      directory
    end
  end

  belongs_to :bundle, counter_cache: :asset_count

  validates :path, presence: true, uniqueness: { scope: :bundle_id }
  validates :storage_key, presence: true
  validates :content_type, presence: true

  def self.file_listing_entries_for(bundle:, prefix:, limit:, offset:)
    rows = connection.exec_query(
      sanitize_sql_array([ <<~SQL.squish, limit.to_i, offset.to_i ])
        SELECT * FROM (#{file_listing_entries_relation_sql(bundle_id: bundle.id, prefix:)}) listing_entries
        ORDER BY directory DESC, name COLLATE NOCASE ASC
        LIMIT ? OFFSET ?
      SQL
    )

    rows.map do |row|
      FileListingEntry.new(
        path: row.fetch("path"),
        name: row.fetch("name"),
        directory: row.fetch("directory").to_i == 1,
        byte_size: row["byte_size"]&.to_i
      )
    end
  end

  def self.file_listing_entry_count_for(bundle:, prefix:)
    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM (#{file_listing_entries_relation_sql(bundle_id: bundle.id, prefix:)}) listing_entries
    SQL
  end

  def has_prerendered_markdown?
    rendered_html.present? && rendered_html_version == BundleMarkdownRenderer::VERSION
  end

  def self.file_listing_entries_relation_sql(bundle_id:, prefix:)
    relative_path_sql = "substr(path, #{prefix.length + 1})"
    slash_index_sql = "instr(#{relative_path_sql}, '/')"
    directory_sql = "CASE WHEN #{slash_index_sql} = 0 THEN 0 ELSE 1 END"
    name_sql = <<~SQL.squish
      CASE
        WHEN #{slash_index_sql} = 0 THEN #{relative_path_sql}
        ELSE substr(#{relative_path_sql}, 1, #{slash_index_sql} - 1)
      END
    SQL
    path_sql = <<~SQL.squish
      CASE
        WHEN #{directory_sql} = 0 THEN #{connection.quote(prefix)} || #{name_sql}
        ELSE #{connection.quote(prefix)} || #{name_sql} || '/'
      END
    SQL
    like_pattern = "#{sanitize_sql_like(prefix)}%"

    sanitize_sql_array([ <<~SQL.squish, bundle_id, like_pattern ])
      SELECT
        #{path_sql} AS path,
        #{name_sql} AS name,
        #{directory_sql} AS directory,
        MAX(CASE WHEN #{directory_sql} = 0 THEN byte_size END) AS byte_size
      FROM bundle_assets
      WHERE bundle_id = ? AND path LIKE ? ESCAPE '\\'
      GROUP BY #{path_sql}, #{name_sql}, #{directory_sql}
    SQL
  end
  private_class_method :file_listing_entries_relation_sql
end
