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
