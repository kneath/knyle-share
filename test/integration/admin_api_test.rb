require "test_helper"
require "cgi"
require "digest"
require "rubygems/package"
require "stringio"
require "zlib"

class AdminApiTest < ActionDispatch::IntegrationTest
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    BundleUpload.delete_all
    Bundle.delete_all
    ApiToken.delete_all

    host! "admin.lvh.me"
    @api_token, @plaintext_token = ApiToken.issue!(label: "CLI")
    @headers = { "Authorization" => "Bearer #{@plaintext_token}" }
  end

  test "rejects requests without an api token" do
    get "/api/v1/bundles/availability", params: { slug: "field-notes" }

    assert_response :unauthorized
  end

  test "checks slug availability" do
    Bundle.create!(
      slug: "field-notes",
      title: "Field Notes",
      source_kind: "file",
      presentation_kind: "markdown_document",
      access_mode: "public",
      status: "active"
    )

    get "/api/v1/bundles/availability", params: { slug: "field-notes" }, headers: @headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["available"]
    assert_equal true, body["exists"]
    assert_equal true, body["replaceable"]
  end

  test "creates an upload and returns ingest metadata" do
    fake_store = Class.new do
      def presign_put(key:, content_type:, expires_in: 15.minutes)
        "https://example.com/upload?key=#{CGI.escape(key)}&type=#{CGI.escape(content_type)}"
      end
    end.new

    BundleIngest::ObjectStore.stub :new, fake_store do
      post "/api/v1/uploads",
        params: {
          upload: {
            slug: "field-notes",
            source_kind: "file",
            original_filename: "field-notes.md",
            access_mode: "protected",
            password: "river maple lantern",
            replace_existing: false
          }
        },
        headers: @headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_match %r{\Auploads/}, body["ingest_key"]
    assert_match %r{\Ahttps://example.com/upload}, body["upload_url"]
    assert @api_token.reload.last_used_at.present?
  end

  test "finalizes and processes an upload into a bundle" do
    upload = BundleUpload.create!(
      slug: "archive-site",
      source_kind: "directory",
      original_filename: "archive-site.tar.gz",
      access_mode: "public",
      replace_existing: false,
      ingest_key: "uploads/u1/archive-site.tar.gz",
      byte_size: 0
    )

    archive_body = build_tar_gz(
      "index.html" => "<h1>Archive Site</h1>",
      "assets/app.css" => "body { color: blue; }"
    )

    fake_store = fake_object_store(
      "uploads/u1/archive-site.tar.gz" => {
        body: archive_body,
        content_type: "application/gzip",
        byte_size: archive_body.bytesize
      }
    )

    BundleIngest::ObjectStore.stub :new, fake_store do
      put "/api/v1/uploads/#{upload.id}", params: { upload: { byte_size: archive_body.bytesize } }, headers: @headers
      assert_response :success
      assert_equal "staged", JSON.parse(response.body)["status"]

      post "/api/v1/uploads/#{upload.id}/process", headers: @headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "ready", body["status"]
    assert_equal "archive-site", body.dig("bundle", "slug")
    assert_equal "static_site", Bundle.find_by!(slug: "archive-site").presentation_kind
  end

  test "returns bundle metadata and creates signed links" do
    bundle = Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern",
      entry_path: "private-brief.pdf",
      content_revision: 2
    )

    get "/api/v1/bundles/private-brief", headers: @headers

    assert_response :success
    metadata = JSON.parse(response.body)
    assert_equal "private-brief", metadata["slug"]
    assert_equal 2, metadata["content_revision"]

    post "/api/v1/bundles/private-brief/links", params: { expires_in: "1_week" }, headers: @headers

    assert_response :created
    link = JSON.parse(response.body)
    assert_match %r{\Ahttps?://private-brief\.share\.lvh\.me/\?access=}, link["url"]
  end

  private

  def fake_object_store(objects)
    Class.new do
      attr_reader :objects

      def initialize(objects)
        @objects = objects.transform_values(&:dup)
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

      def copy(source_key:, destination_key:)
        attributes = objects.fetch(source_key)
        objects[destination_key] = attributes.merge(body: attributes[:body].dup)
      end

      def delete(key:)
        objects.delete(key)
      end

      def presign_put(key:, content_type:, expires_in: 15.minutes)
        "https://example.com/upload?key=#{CGI.escape(key)}"
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
