def seed_bundle(slug:, title:, source_kind:, presentation_kind:, access_mode:, status:, password:, byte_size:, asset_count:, total_views_count:, unique_protected_viewers_count:, entry_path:, created_at:, last_viewed_at:, last_replaced_at:, content_revision:)
  bundle = Bundle.find_or_initialize_by(slug:)
  bundle.assign_attributes(
    title:,
    source_kind:,
    presentation_kind:,
    access_mode:,
    status:,
    password_session_ttl_seconds: 1.day.to_i,
    entry_path:,
    byte_size:,
    total_views_count:,
    unique_protected_viewers_count:,
    last_viewed_at:,
    last_replaced_at:,
    content_revision:
  )

  if password.present?
    bundle.password = password
  else
    bundle.password_digest = nil
  end

  bundle.save!
  bundle.update_columns(created_at:, updated_at: [last_viewed_at, last_replaced_at, created_at].compact.max)

  bundle.assets.destroy_all

  sizes = Array.new(asset_count, byte_size / asset_count)
  sizes[-1] += byte_size - sizes.sum

  asset_count.times do |index|
    path =
      if index.zero?
        entry_path
      elsif source_kind == "directory"
        "files/item-#{index + 1}.dat"
      else
        "#{File.basename(entry_path, ".*")}-#{index + 1}#{File.extname(entry_path)}"
      end

    bundle.assets.create!(
      path:,
      storage_key: "bundles/#{bundle.id}/#{bundle.content_revision}/#{path}",
      content_type: content_type_for(path),
      byte_size: sizes[index],
      checksum: "seed-#{bundle.slug}-#{index + 1}"
    )
  end
end

def content_type_for(path)
  case File.extname(path)
  when ".html" then "text/html"
  when ".md" then "text/markdown"
  when ".pdf" then "application/pdf"
  when ".png" then "image/png"
  else "application/octet-stream"
  end
end

seed_bundle(
  slug: "poke-recipes",
  title: "Poke Recipes",
  source_kind: "directory",
  presentation_kind: "static_site",
  access_mode: "protected",
  status: "active",
  password: "river maple lantern",
  byte_size: 2.4.megabytes.to_i,
  asset_count: 14,
  total_views_count: 12,
  unique_protected_viewers_count: 4,
  entry_path: "index.html",
  created_at: Time.zone.parse("2026-03-13 10:00:00"),
  last_viewed_at: 2.hours.ago,
  last_replaced_at: nil,
  content_revision: 1
)

seed_bundle(
  slug: "landscaping-project",
  title: "Landscaping Project",
  source_kind: "file",
  presentation_kind: "single_download",
  access_mode: "public",
  status: "active",
  password: nil,
  byte_size: 43.megabytes,
  asset_count: 1,
  total_views_count: 3,
  unique_protected_viewers_count: 0,
  entry_path: "landscaping-project.pdf",
  created_at: Time.zone.parse("2026-03-10 09:00:00"),
  last_viewed_at: 1.day.ago,
  last_replaced_at: Time.zone.parse("2026-03-18 12:00:00"),
  content_revision: 2
)

seed_bundle(
  slug: "sierra-draft",
  title: "Sierra Draft",
  source_kind: "file",
  presentation_kind: "markdown_document",
  access_mode: "protected",
  status: "active",
  password: "cedar lantern harbor",
  byte_size: 186.kilobytes,
  asset_count: 1,
  total_views_count: 8,
  unique_protected_viewers_count: 3,
  entry_path: "sierra-draft.md",
  created_at: Time.zone.parse("2026-03-08 14:00:00"),
  last_viewed_at: 3.days.ago,
  last_replaced_at: nil,
  content_revision: 1
)

seed_bundle(
  slug: "old-mockups",
  title: "Old Mockups",
  source_kind: "directory",
  presentation_kind: "file_listing",
  access_mode: "public",
  status: "disabled",
  password: nil,
  byte_size: 12.megabytes,
  asset_count: 22,
  total_views_count: 0,
  unique_protected_viewers_count: 0,
  entry_path: "index.txt",
  created_at: Time.zone.parse("2026-02-22 15:00:00"),
  last_viewed_at: nil,
  last_replaced_at: Time.zone.parse("2026-03-01 11:00:00"),
  content_revision: 2
)
