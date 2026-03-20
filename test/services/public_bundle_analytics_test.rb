require "test_helper"

class PublicBundleAnalyticsTest < ActiveSupport::TestCase
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    Bundle.delete_all
  end

  test "increments total views and unique protected viewers without double-counting a session" do
    bundle = Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern"
    )
    viewer_session = bundle.viewer_sessions.create!(
      access_revision: bundle.access_revision,
      token_digest: "digest",
      expires_at: 1.day.from_now
    )

    analytics = PublicBundleAnalytics.new

    analytics.record_view!(bundle:, viewer_session:, access_method: "password_session", request_path: "/")
    analytics.record_view!(bundle:, viewer_session:, access_method: "password_session", request_path: "/download")

    bundle.reload
    assert_equal 2, bundle.total_views_count
    assert_equal 1, bundle.unique_protected_viewers_count
    assert_equal 2, bundle.bundle_views.count
    assert_equal 1, BundleUniqueViewer.where(bundle:, viewer_session:).count
  end
end
