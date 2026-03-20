require "test_helper"

class BundleUploadTest < ActiveSupport::TestCase
  setup do
    BundleUpload.delete_all
  end

  test "requires a password digest for protected uploads" do
    upload = build_upload(access_mode: "protected", password_digest: nil)

    assert_not upload.valid?
    assert_includes upload.errors[:password_digest], "must be set for protected uploads"
  end

  test "rejects reserved slugs" do
    upload = build_upload(slug: "api")

    assert_not upload.valid?
    assert_includes upload.errors[:slug], "is reserved"
  end

  test "status predicates reflect the current state" do
    upload = build_upload

    assert_predicate upload, :pending?
    assert_not_predicate upload, :ready?

    upload.status = "ready"

    assert_predicate upload, :ready?
    assert_not_predicate upload, :pending?
  end

  test "mark helpers persist transitions" do
    upload = build_upload
    upload.save!

    upload.mark_staged!
    assert_predicate upload.reload, :staged?

    upload.mark_processing!
    assert_predicate upload.reload, :processing?

    upload.mark_failed!("broken")
    assert_predicate upload.reload, :failed?
    assert_equal "broken", upload.error_message

    upload.mark_ready!
    assert_predicate upload.reload, :ready?
    assert_nil upload.error_message
  end

  private

  def build_upload(**attributes)
    defaults = {
      slug: "sample-upload",
      source_kind: "file",
      original_filename: "sample.md",
      access_mode: "public",
      password_digest: nil,
      replace_existing: false,
      ingest_key: "uploads/sample-upload",
      status: "pending",
      byte_size: 123
    }

    BundleUpload.new(defaults.merge(attributes))
  end
end
