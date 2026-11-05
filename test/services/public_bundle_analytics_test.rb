require "test_helper"

class PublicBundleAnalyticsTest < ActiveSupport::TestCase
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
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

  test "enqueues view recording jobs" do
    bundle = Bundle.create!(
      slug: "field-notes",
      title: "Field Notes",
      source_kind: "file",
      presentation_kind: "markdown_document",
      access_mode: "public",
      status: "active"
    )

    analytics = PublicBundleAnalytics.new

    assert_enqueued_with(
      job: RecordPublicBundleViewJob,
      args: [ {
        bundle_id: bundle.id,
        viewer_session_id: nil,
        access_method: "public",
        request_path: "/"
      } ]
    ) do
      analytics.record_view_later(bundle:, access_method: "public", request_path: "/")
    end
  end

  test "a view is recorded in one transaction with one bundle update" do
    @bundle = Bundle.create!(slug: "private-brief", title: "Private Brief", source_kind: "file", presentation_kind: "single_download",
      access_mode: "protected", status: "active", password: "river maple lantern")
    session = @bundle.viewer_sessions.create!(token_digest: SecureRandom.hex(16), expires_at: 1.day.from_now, last_seen_at: Time.current)
    analytics = PublicBundleAnalytics.new
    analytics.record_view!(bundle: @bundle, viewer_session: session, access_method: "password", request_path: "/")
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] if payload[:sql].match?(/\A(INSERT|UPDATE|BEGIN|SAVEPOINT)/i)
    end

    begin
      analytics.record_view!(bundle: @bundle, viewer_session: session, access_method: "password", request_path: "/")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    # Tests run inside a transaction, so the view's transaction is a savepoint here.
    assert_equal 1, statements.count { |sql| sql.match?(/\A(BEGIN|SAVEPOINT)/i) }
    assert_equal 1, statements.count { |sql| sql.match?(/\AUPDATE "bundles"/) }
    @bundle.reload
    assert_equal 2, @bundle.total_views_count
    assert_equal 1, @bundle.unique_protected_viewers_count
  end
end
