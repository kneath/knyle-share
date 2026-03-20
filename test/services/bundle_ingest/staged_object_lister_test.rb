require "test_helper"
require "rubygems/package"
require "zlib"

class BundleIngest::StagedObjectListerTest < ActiveSupport::TestCase
  test "uses the original filename for a staged file upload" do
    upload = BundleUpload.new(
      slug: "field-notes",
      source_kind: "file",
      original_filename: "field-notes.md",
      access_mode: "public",
      ingest_key: "uploads/field-notes/uploaded-object",
      byte_size: 128
    )

    entries = BundleIngest::StagedObjectLister.call(
      bundle_upload: upload,
      object_store: fake_store(
        "uploads/field-notes/uploaded-object" => { byte_size: 128, content_type: "text/markdown" }
      )
    )

    assert_equal ["field-notes.md"], entries.map(&:path)
  end

  test "rejects path traversal in directory uploads" do
    upload = BundleUpload.new(
      slug: "site",
      source_kind: "directory",
      original_filename: "site.tar.gz",
      access_mode: "public",
      ingest_key: "uploads/site",
      byte_size: 128
    )

    error = assert_raises(BundleIngest::StagedObjectLister::Error) do
      BundleIngest::StagedObjectLister.call(
        bundle_upload: upload,
        object_store: fake_store(
          "uploads/site/../../secrets.txt" => { byte_size: 10, content_type: "text/plain" }
        )
      )
    end

    assert_match "Path traversal", error.message
  end

  test "extracts entries from a tar gz directory upload" do
    upload = BundleUpload.new(
      slug: "site",
      source_kind: "directory",
      original_filename: "site.tar.gz",
      access_mode: "public",
      ingest_key: "uploads/site.tar.gz",
      byte_size: 128
    )

    archive_body = build_tar_gz(
      "index.html" => "<h1>Hello</h1>",
      "assets/app.css" => "body { color: red; }"
    )

    entries = BundleIngest::StagedObjectLister.call(
      bundle_upload: upload,
      object_store: fake_store(
        "uploads/site.tar.gz" => {
          body: archive_body,
          byte_size: archive_body.bytesize,
          content_type: "application/gzip"
        }
      )
    )

    assert_equal %w[assets/app.css index.html], entries.map(&:path)
    assert entries.all? { |entry| entry.source_key.nil? }
    assert entries.all? { |entry| entry.body.present? }
  end

  private

  def fake_store(objects)
    Class.new do
      def initialize(objects)
        @objects = objects
      end

      def list(prefix:)
        @objects
          .select { |key, _| key.start_with?(prefix) }
          .map do |key, attributes|
            BundleIngest::ObjectStore::StoredObject.new(
              key:,
              content_type: attributes.fetch(:content_type),
              byte_size: attributes.fetch(:byte_size),
              checksum: attributes[:checksum]
            )
          end
      end

      def read(key:)
        @objects.fetch(key).fetch(:body)
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
