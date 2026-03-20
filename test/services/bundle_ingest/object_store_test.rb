require "test_helper"
require "aws-sdk-s3"

class BundleIngestObjectStoreTest < ActiveSupport::TestCase
  test "presign_put passes an integer expiration to aws" do
    captured_options = nil
    fake_presigner = Class.new do
      def initialize(callback)
        @callback = callback
      end

      def presigned_url(operation, **options)
        @callback.call(operation, options)
        "https://example.com/presigned-upload"
      end
    end.new(lambda { |operation, options| captured_options = options.merge(operation:) })

    Aws::S3::Presigner.stub :new, fake_presigner do
      object_store = BundleIngest::ObjectStore.new(bucket: "knyle-share-test", s3_client: Object.new)
      url = object_store.presign_put(key: "uploads/test/file.md", content_type: "text/markdown")

      assert_equal "https://example.com/presigned-upload", url
      assert_equal :put_object, captured_options[:operation]
      assert_equal "knyle-share-test", captured_options[:bucket]
      assert_equal "uploads/test/file.md", captured_options[:key]
      assert_equal "text/markdown", captured_options[:content_type]
      assert_equal 900, captured_options[:expires_in]
      assert_kind_of Integer, captured_options[:expires_in]
    end
  end
end
