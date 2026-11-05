require "test_helper"

class BundleStorageTest < ActiveSupport::TestCase
  test "fetch returns body and metadata for a bundle asset" do
    asset = BundleAsset.new(
      path: "files/report.pdf",
      storage_key: "bundles/1/1/files/report.pdf",
      content_type: "application/pdf"
    )

    body = StringIO.new("pdf-bytes")
    response = Struct.new(:body).new(body)
    s3_client = Class.new do
      def initialize(response, expected_bucket:, expected_key:)
        @response = response
        @expected_bucket = expected_bucket
        @expected_key = expected_key
      end

      def get_object(bucket:, key:)
        raise "Unexpected bucket" unless bucket == @expected_bucket
        raise "Unexpected key" unless key == @expected_key

        @response
      end
    end.new(response, expected_bucket: "bucket-name", expected_key: asset.storage_key)

    result = BundleStorage.new(bucket: "bucket-name", s3_client:).fetch(asset)

    assert_equal "pdf-bytes", result[:body]
    assert_equal "application/pdf", result[:content_type]
    assert_equal "report.pdf", result[:filename]
  end

  test "stable download URLs are identical within a window and outlive a cached redirect" do
    asset = BundleAsset.new(path: "assets/app.js", storage_key: "bundles/1/1/assets/app.js", content_type: "text/javascript")
    storage = BundleStorage.new(
      bucket: "knyle-share-test",
      s3_client: Aws::S3::Client.new(region: "us-west-2", credentials: Aws::Credentials.new("key", "secret"), stub_responses: true)
    )
    window_start = Time.utc(2026, 11, 5, 12, 0, 0)
    url_at = ->(time, **options) { storage.download_url(asset, disposition: "inline", expires_in: 300, now: time, **options) }

    first = url_at.call(window_start + 1, stable: true)
    assert_equal first, url_at.call(window_start + 299, stable: true)
    assert_not_equal first, url_at.call(window_start + 300, stable: true)

    query = Rack::Utils.parse_query(URI(first).query)
    assert_equal "20261105T120000Z", query["X-Amz-Date"]
    assert_equal "600", query["X-Amz-Expires"]
    signed_at = Time.strptime(query["X-Amz-Date"], "%Y%m%dT%H%M%S%z")
    expires_at = signed_at + query["X-Amz-Expires"].to_i
    # Requested at the very end of the window, the URL still outlives a redirect cached for 300 s.
    assert_operator expires_at - (window_start + 299), :>=, 300

    unstable = Rack::Utils.parse_query(URI(url_at.call(window_start + 42)).query)
    assert_equal "300", unstable["X-Amz-Expires"]
  end

  test "download_url presigns a short-lived get with content headers" do
    asset = BundleAsset.new(
      path: "files/report.pdf",
      storage_key: "bundles/1/1/files/report.pdf",
      content_type: "application/pdf"
    )

    fake_client = Object.new
    fake_presigner = Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def presigned_url(operation, **options)
        calls << [operation, options]
        "https://downloads.example.test/report.pdf"
      end
    end.new

    Aws::S3::Presigner.stub :new, fake_presigner do
      storage = BundleStorage.new(bucket: "bucket-name", s3_client: fake_client)
      url = storage.download_url(asset, disposition: "attachment")

      assert_equal "https://downloads.example.test/report.pdf", url
      operation, options = fake_presigner.calls.fetch(0)
      assert_equal :get_object, operation
      assert_equal "bucket-name", options[:bucket]
      assert_equal asset.storage_key, options[:key]
      assert_equal "application/pdf", options[:response_content_type]
      assert_match(/attachment/, options[:response_content_disposition])
      assert_match(/report\.pdf/, options[:response_content_disposition])
    end
  end

  test "markdown rendering can be disabled for oversized files" do
    asset = BundleAsset.new(
      path: "notes.md",
      storage_key: "bundles/1/1/notes.md",
      content_type: "text/markdown",
      byte_size: 2.megabytes
    )

    storage = BundleStorage.new(
      bucket: "bucket-name",
      s3_client: Object.new,
      env: { "INLINE_MARKDOWN_RENDER_MAX_BYTES" => "1024" }
    )

    assert_not storage.render_markdown_inline?(asset)
  end
end
