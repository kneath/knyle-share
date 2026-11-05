require "test_helper"

class BundleTest < ActiveSupport::TestCase
  test "protected bundles require a password digest" do
    bundle = Bundle.new(
      slug: "protected-bundle",
      title: "Protected Bundle",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active"
    )

    assert_not bundle.valid?
    assert_includes bundle.errors[:password_digest], "must be set for protected bundles"
  end

  test "destroying a bundle deletes its dependents in a few statements" do
    bundle = Bundle.create!(slug: "busy-bundle", title: "Busy", source_kind: "file", presentation_kind: "single_download", access_mode: "public", status: "active")
    3.times { |index| bundle.assets.create!(path: "file-#{index}.txt", storage_key: "bundles/#{bundle.id}/file-#{index}.txt", content_type: "text/plain", byte_size: 1) }
    sessions = 5.times.map { bundle.viewer_sessions.create!(token_digest: SecureRandom.hex(32), expires_at: 1.day.from_now) }
    sessions.each do |session|
      BundleUniqueViewer.create!(bundle:, viewer_session: session, first_viewed_at: Time.current)
      4.times { BundleView.create!(bundle:, viewer_session: session, access_method: "password", request_path: "/", viewed_at: Time.current) }
    end

    deletes = count_queries(/\ADELETE/) { bundle.destroy! }

    assert_operator deletes, :<=, 6
    assert_equal 0, BundleAsset.where(bundle_id: bundle.id).count
    assert_equal 0, BundleView.where(bundle_id: bundle.id).count
    assert_equal 0, BundleUniqueViewer.where(bundle_id: bundle.id).count
    assert_equal 0, ViewerSession.where(bundle_id: bundle.id).count
    assert_equal 3, StorageCleanup.last.object_keys.count { |key| key.start_with?("bundles/#{bundle.id}/") }
  end

  test "reserved slugs are rejected" do
    bundle = build_bundle(slug: "api")

    assert_not bundle.valid?
    assert_includes bundle.errors[:slug], "is reserved"
  end

  private

  def build_bundle(**attributes)
    defaults = {
      slug: "sample-bundle",
      title: "Sample Bundle",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "public",
      status: "active"
    }

    Bundle.new(defaults.merge(attributes))
  end


  def count_queries(pattern)
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql].match?(pattern)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
