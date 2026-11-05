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

  test "copy escapes the source key for CopySource" do
    captured = nil
    s3_client = Object.new
    s3_client.define_singleton_method(:copy_object) { |**options| captured = options }

    object_store = BundleIngest::ObjectStore.new(bucket: "knyle-share-test", s3_client:)
    object_store.copy(source_key: "uploads/abc/Notes 100% done?+résumé.md", destination_key: "bundles/1/notes.md")

    assert_equal "knyle-share-test/uploads/abc/Notes%20100%25%20done%3F%2Br%C3%A9sum%C3%A9.md", captured[:copy_source]
    assert_equal "bundles/1/notes.md", captured[:key]
  end

  test "delete_many sends one DeleteObjects request per 1,000 keys" do
    batches = []
    s3_client = Object.new
    s3_client.define_singleton_method(:delete_objects) do |bucket:, delete:|
      batches << delete.fetch(:objects).map { |object| object.fetch(:key) }
      Struct.new(:errors).new([])
    end

    keys = (1..2_500).map { |index| "bundles/1/file-#{index}" }
    BundleIngest::ObjectStore.new(bucket: "knyle-share-test", s3_client:).delete_many(keys:)

    assert_equal [1_000, 1_000, 500], batches.map(&:size)
    assert_equal keys, batches.flatten
  end

  test "delete_many raises when S3 reports keys it could not delete" do
    s3_client = Object.new
    s3_client.define_singleton_method(:delete_objects) do |**|
      Struct.new(:errors).new([Struct.new(:key, :code).new("bundles/1/a.txt", "AccessDenied")])
    end

    error = assert_raises(Aws::S3::Errors::ServiceError) do
      BundleIngest::ObjectStore.new(bucket: "knyle-share-test", s3_client:).delete_many(keys: ["bundles/1/a.txt"])
    end

    assert_match "bundles/1/a.txt (AccessDenied)", error.message
  end

  test "any? asks S3 for at most one key" do
    calls = []
    s3_client = Object.new
    s3_client.define_singleton_method(:list_objects_v2) do |**options|
      calls << options
      Struct.new(:contents).new(options[:prefix] == "uploads/site/" ? [Struct.new(:key).new("uploads/site/index.html")] : [])
    end
    store = BundleIngest::ObjectStore.new(bucket: "knyle-share-test", s3_client:)

    assert store.any?(prefix: "uploads/site/")
    assert_not store.any?(prefix: "uploads/empty/")
    assert_equal [1, 1], calls.map { |options| options[:max_keys] }
  end
end
