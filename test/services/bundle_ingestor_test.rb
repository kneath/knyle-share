require "test_helper"
require "digest"
require "rubygems/package"
require "zlib"

class BundleIngestorTest < ActiveSupport::TestCase
  setup do
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    BundleUpload.delete_all
    Bundle.delete_all
  end

  test "publishes a single file upload into a new bundle" do
    upload = BundleUpload.create!(
      slug: "field-notes",
      source_kind: "file",
      original_filename: "field-notes.md",
      access_mode: "protected",
      password: "river maple lantern",
      replace_existing: false,
      ingest_key: "uploads/u1/field-notes.md",
      byte_size: 24
    )

    store = fake_store(
      "uploads/u1/field-notes.md" => {
        body: "# Hello",
        content_type: "text/markdown",
        byte_size: 24,
        checksum: "abc123"
      }
    )

    result = BundleIngestor.new(bundle_upload: upload, object_store: store).call
    bundle = result.bundle.reload

    assert_equal "ready", upload.reload.status
    assert_equal "markdown_document", bundle.presentation_kind
    assert bundle.authenticate("river maple lantern")
    assert_equal 1, bundle.content_revision
    assert_equal 1, bundle.assets.count
    assert_equal ["uploads/u1/field-notes.md"], store.deleted_keys
    assert store.objects.key?("bundles/#{bundle.id}/1/field-notes.md")
  end

  test "publishes a directory upload as a static site" do
    upload = BundleUpload.create!(
      slug: "design-review",
      source_kind: "directory",
      original_filename: "design-review.tar.gz",
      access_mode: "public",
      replace_existing: false,
      ingest_key: "uploads/u2/design-review",
      byte_size: 300
    )

    store = fake_store(
      "uploads/u2/design-review/index.html" => {
        body: "<h1>Review</h1>",
        content_type: "text/html",
        byte_size: 120
      },
      "uploads/u2/design-review/assets/app.css" => {
        body: "body { color: red; }",
        content_type: "text/css",
        byte_size: 180
      }
    )

    result = BundleIngestor.new(bundle_upload: upload, object_store: store).call
    bundle = result.bundle.reload

    assert_equal "static_site", bundle.presentation_kind
    assert_equal "index.html", bundle.entry_path
    assert_equal 2, bundle.assets.count
    assert_equal 300, bundle.byte_size
    assert_equal %w[assets/app.css index.html], bundle.assets.order(:path).pluck(:path)
  end

  test "publishes a tar gz directory upload into extracted bundle assets" do
    archive_body = build_tar_gz(
      "index.html" => "<h1>Archive Site</h1>",
      "assets/app.css" => "body { color: blue; }"
    )

    upload = BundleUpload.create!(
      slug: "archive-site",
      source_kind: "directory",
      original_filename: "archive-site.tar.gz",
      access_mode: "public",
      replace_existing: false,
      ingest_key: "uploads/u-archive/archive-site.tar.gz",
      byte_size: archive_body.bytesize
    )

    store = fake_store(
      "uploads/u-archive/archive-site.tar.gz" => {
        body: archive_body,
        content_type: "application/gzip",
        byte_size: archive_body.bytesize
      }
    )

    result = BundleIngestor.new(bundle_upload: upload, object_store: store).call
    bundle = result.bundle.reload

    assert_equal "static_site", bundle.presentation_kind
    assert_equal %w[assets/app.css index.html], bundle.assets.order(:path).pluck(:path)
    assert store.objects.key?("bundles/#{bundle.id}/1/index.html")
    assert store.objects.key?("bundles/#{bundle.id}/1/assets/app.css")
  end

  test "replacement preserves analytics while revoking prior access grants" do
    bundle = Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      password: "river maple lantern",
      content_revision: 1,
      total_views_count: 7,
      unique_protected_viewers_count: 2,
      last_viewed_at: 1.hour.ago,
      entry_path: "private-brief.pdf",
      byte_size: 20
    )
    bundle.assets.create!(
      path: "private-brief.pdf",
      storage_key: "bundles/#{bundle.id}/1/private-brief.pdf",
      content_type: "application/pdf",
      byte_size: 20,
      checksum: "old"
    )
    session = bundle.viewer_sessions.create!(
      access_revision: bundle.access_revision,
      token_digest: "token",
      expires_at: 1.day.from_now,
      last_seen_at: Time.current
    )
    bundle.bundle_views.create!(
      viewer_session: session,
      access_method: "password_session",
      request_path: "/private-brief",
      viewed_at: Time.current
    )

    upload = BundleUpload.create!(
      slug: "private-brief",
      source_kind: "file",
      original_filename: "private-brief-v2.pdf",
      access_mode: "public",
      replace_existing: true,
      ingest_key: "uploads/u3/private-brief-v2.pdf",
      byte_size: 40
    )

    store = fake_store(
      "uploads/u3/private-brief-v2.pdf" => {
        body: "%PDF-1.7 new",
        content_type: "application/pdf",
        byte_size: 40,
        checksum: "new"
      },
      "bundles/#{bundle.id}/1/private-brief.pdf" => {
        body: "%PDF-1.7 old",
        content_type: "application/pdf",
        byte_size: 20,
        checksum: "old"
      }
    )

    result = BundleIngestor.new(bundle_upload: upload, object_store: store).call
    replaced_bundle = result.bundle.reload

    assert_equal bundle.id, replaced_bundle.id
    assert_equal 2, replaced_bundle.content_revision
    assert_equal 2, replaced_bundle.access_revision
    assert_equal 7, replaced_bundle.total_views_count
    assert_equal 2, replaced_bundle.unique_protected_viewers_count
    assert_equal 1, replaced_bundle.viewer_sessions.count
    assert_equal [1], replaced_bundle.viewer_sessions.pluck(:access_revision)
    assert_equal 1, replaced_bundle.bundle_views.count
    assert_equal "public", replaced_bundle.access_mode
    assert_nil replaced_bundle.password_digest
    assert_equal ["private-brief-v2.pdf"], replaced_bundle.assets.pluck(:path)
    assert_includes store.deleted_keys, "uploads/u3/private-brief-v2.pdf"
    assert_includes store.deleted_keys, "bundles/#{bundle.id}/1/private-brief.pdf"
    assert store.objects.key?("bundles/#{bundle.id}/2/private-brief-v2.pdf")
  end

  test "fails when a slug already exists without replacement enabled" do
    Bundle.create!(
      slug: "field-notes",
      title: "Field Notes",
      source_kind: "file",
      presentation_kind: "markdown_document",
      access_mode: "public",
      status: "active"
    )

    upload = BundleUpload.create!(
      slug: "field-notes",
      source_kind: "file",
      original_filename: "field-notes.md",
      access_mode: "public",
      replace_existing: false,
      ingest_key: "uploads/u4/field-notes.md",
      byte_size: 24
    )

    error = assert_raises(BundleIngestor::Error) do
      BundleIngestor.new(
        bundle_upload: upload,
        object_store: fake_store(
          "uploads/u4/field-notes.md" => {
            body: "# Hello",
            content_type: "text/markdown",
            byte_size: 24
          }
        )
      ).call
    end

    assert_match "already exists", error.message
    assert_equal "failed", upload.reload.status
  end

  private

  def fake_store(objects)
    Class.new do
      attr_reader :objects, :copies, :deleted_keys

      def initialize(objects)
        @objects = objects.transform_values(&:dup)
        @copies = []
        @deleted_keys = []
      end

      def list(prefix:)
        objects
          .sort
          .filter_map do |key, attributes|
            next unless key.start_with?(prefix)

            BundleIngest::ObjectStore::StoredObject.new(
              key:,
              content_type: attributes.fetch(:content_type),
              byte_size: attributes.fetch(:byte_size),
              checksum: attributes[:checksum]
            )
          end
      end

      def copy(source_key:, destination_key:)
        attributes = objects.fetch(source_key)
        objects[destination_key] = attributes.merge(body: attributes[:body].dup)
        copies << [source_key, destination_key]
      end

      def read(key:)
        objects.fetch(key).fetch(:body)
      end

      def write(key:, body:, content_type:)
        objects[key] = {
          body: body.dup,
          content_type:,
          byte_size: body.bytesize,
          checksum: Digest::SHA256.hexdigest(body)
        }
      end

      def delete(key:)
        deleted_keys << key
        objects.delete(key)
      end
    end.new(objects)
  end

  def build_tar_gz(files)
    tar_io = StringIO.new

    Gem::Package::TarWriter.new(tar_io) do |tar|
      files.each do |path, body|
        tar.add_file_simple(path, 0o644, body.bytesize) { |io| io.write(body) }
      end
    end

    tar_io.rewind

    gz_io = StringIO.new
    Zlib::GzipWriter.wrap(gz_io) { |gzip| gzip.write(tar_io.string) }
    gz_io.string
  end
end
