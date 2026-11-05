class PublicBundleAnalytics
  def record_view_later(bundle:, access_method:, request_path:, viewer_session: nil)
    RecordPublicBundleViewJob.perform_later(
      bundle_id: bundle.id,
      viewer_session_id: viewer_session&.id,
      access_method:,
      request_path:
    )
  end

  # One short transaction per view: a unique-viewer insert that skips
  # duplicates instead of raising, the view row, and a single UPDATE for both
  # counters and last_viewed_at. Fewer write-lock acquisitions keep views
  # from queueing behind each other on SQLite.
  def record_view!(bundle:, access_method:, request_path:, viewer_session: nil)
    viewed_at = Time.current

    ActiveRecord::Base.transaction do
      new_unique_viewer = register_unique_viewer(bundle:, viewer_session:, viewed_at:)

      BundleView.create!(
        bundle:,
        viewer_session:,
        access_method:,
        request_path:,
        viewed_at:
      )

      Bundle.where(id: bundle.id).update_all([
        "total_views_count = total_views_count + 1, " \
        "unique_protected_viewers_count = unique_protected_viewers_count + ?, " \
        "last_viewed_at = ?",
        new_unique_viewer ? 1 : 0,
        viewed_at
      ])
    end
  end

  private

  def register_unique_viewer(bundle:, viewer_session:, viewed_at:)
    return false if viewer_session.blank?

    inserted = BundleUniqueViewer.insert_all(
      [{ bundle_id: bundle.id, viewer_session_id: viewer_session.id, first_viewed_at: viewed_at }],
      unique_by: %i[bundle_id viewer_session_id],
      returning: %w[id]
    )
    inserted.rows.any?
  end
end
