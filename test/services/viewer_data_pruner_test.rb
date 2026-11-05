require "test_helper"

class ViewerDataPrunerTest < ActiveSupport::TestCase
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all

    @bundle = Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      password: "river maple lantern",
      status: "active",
      total_views_count: 40,
      unique_protected_viewers_count: 7
    )
  end

  test "deletes views past the retention window and keeps recent ones" do
    old_view = create_view!(viewed_at: 91.days.ago)
    recent_view = create_view!(viewed_at: 89.days.ago)

    ViewerDataPruner.run

    assert_not BundleView.exists?(old_view.id)
    assert BundleView.exists?(recent_view.id)
  end

  test "deletes long-expired sessions with their unique-viewer rows and detaches their views" do
    expired = create_session!(expires_at: 2.days.ago)
    BundleUniqueViewer.create!(bundle: @bundle, viewer_session: expired, first_viewed_at: 3.days.ago)
    expired_view = create_view!(viewed_at: 3.days.ago, viewer_session: expired)
    just_expired = create_session!(expires_at: 1.hour.ago)
    live = create_session!(expires_at: 1.day.from_now)
    BundleUniqueViewer.create!(bundle: @bundle, viewer_session: live, first_viewed_at: 1.hour.ago)

    ViewerDataPruner.run

    assert_not ViewerSession.exists?(expired.id)
    assert_empty BundleUniqueViewer.where(viewer_session_id: expired.id)
    assert_nil expired_view.reload.viewer_session_id
    assert ViewerSession.exists?(just_expired.id)
    assert ViewerSession.exists?(live.id)
    assert_equal 1, BundleUniqueViewer.where(viewer_session_id: live.id).count
  end

  test "leaves the bundle's view counters alone" do
    create_view!(viewed_at: 200.days.ago, viewer_session: create_session!(expires_at: 100.days.ago))

    ViewerDataPruner.run

    @bundle.reload
    assert_equal 40, @bundle.total_views_count
    assert_equal 7, @bundle.unique_protected_viewers_count
  end

  test "publishing maintenance runs the pruner" do
    old_view = create_view!(viewed_at: 1.year.ago)

    PublishingMaintenance.run

    assert_not BundleView.exists?(old_view.id)
  end

  private

  def create_session!(expires_at:)
    @bundle.viewer_sessions.create!(token_digest: SecureRandom.hex(32), expires_at:, access_revision: @bundle.access_revision)
  end

  def create_view!(viewed_at:, viewer_session: nil)
    BundleView.create!(bundle: @bundle, viewer_session:, access_method: "password", request_path: "/", viewed_at:)
  end
end
