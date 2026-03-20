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
end
