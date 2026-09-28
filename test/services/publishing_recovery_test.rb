require "test_helper"
require_relative "../support/memory_object_store"

class PublishingRecoveryTest < ActiveSupport::TestCase
  setup do
    @store = MemoryObjectStore.new
    @upload = BundleUpload.create!(slug: "recovery-test", source_kind: "file", original_filename: "notes.md", access_mode: "public", ingest_key: "uploads/recovery/notes.md", status: "staged")
    @store.write(key: @upload.ingest_key, body: "# Hello", content_type: "text/markdown")
  end

  test "failed preparation retries staged data without reuploading" do
    @store.fail_writes = true
    assert_raises(BundleIngestor::Error) { ingest }
    assert @upload.reload.failed?
    assert @store.objects.key?(@upload.ingest_key)
    @store.fail_writes = false
    bundle = ingest.bundle
    assert_equal "ready", @upload.reload.status
    assert_equal 1, bundle.assets.count
    assert_equal bundle.id, ingest.bundle.id
  end

  test "storage IO happens outside the publish transaction" do
    # Rails wraps this test in a transaction; ingest must not add its own write
    # transaction while copying bytes from storage.
    depth = ActiveRecord::Base.connection.open_transactions
    @store.before_copy = -> { assert_equal depth, ActiveRecord::Base.connection.open_transactions }
    ingest
  end

  test "canceled processing cannot commit its prepared files" do
    @store.before_copy = -> { @upload.update!(status: "canceled", processing_token: nil) }
    assert_no_difference "Bundle.count" do
      assert_raises(BundleIngestor::Error) { ingest }
    end
    assert_equal "canceled", @upload.reload.status
    assert @store.objects.keys.none? { |key| key.start_with?("bundles/") }
  end

  test "storage cleanup survives failure and can be retried" do
    cleanup = StorageCleanup.schedule!([@upload.ingest_key], label: "Test cleanup")
    @store.fail_deletes = true
    cleanup.perform!(store: @store)
    assert_equal 1, cleanup.reload.attempts
    assert cleanup.last_error.present?
    @store.fail_deletes = false
    cleanup.perform!(store: @store)
    assert_nil StorageCleanup.find_by(id: cleanup.id)
    assert_empty @store.objects
  end

  test "replacement refuses to restore access settings changed since upload creation" do
    bundle = Bundle.create!(slug: @upload.slug, title: "Current title", source_kind: "file", presentation_kind: "single_download", access_mode: "protected", password: "first-password")
    @upload.update!(replace_existing: true, access_mode: "protected", password_digest: bundle.password_digest,
      expected_content_revision: bundle.content_revision, expected_access_revision: bundle.access_revision)
    bundle.set_password!("changed-password")
    assert_raises(BundleIngestor::Error) { ingest }
    assert bundle.reload.authenticate("changed-password")
    assert_equal 1, bundle.content_revision
  end

  test "queue failure does not lose durable cleanup records" do
    StorageCleanupJob.stub :perform_later, ->(*) { raise IOError, "Queue unavailable" } do
      cleanup = StorageCleanup.schedule!(["test/key"], label: "Durable cleanup")
      cleanup.enqueue_cleanup
      assert StorageCleanup.exists?(cleanup.id)
    end
  end

  test "safe return paths reject external or ambiguous redirects" do
    ["//evil.test", "https://evil.test", "/\\evil.test", "/%2fevil.test", "/\nnext"].each do |path|
      assert_equal "/", SafeReturnPath.call(path)
    end
    assert_equal "/nested/file.pdf?download=1", SafeReturnPath.call("/nested/file.pdf?download=1")
  end

  private
  def ingest
    BundleIngestor.new(bundle_upload: @upload, object_store: @store).call
  end
end
