class PublicBundleAnalytics
  def record_view!(bundle:, access_method:, request_path:, viewer_session: nil)
    viewed_at = Time.current
    unique_viewer_increment = register_unique_viewer(bundle:, viewer_session:, viewed_at:)

    BundleView.create!(
      bundle:,
      viewer_session:,
      access_method:,
      request_path:,
      viewed_at:
    )

    updates = { total_views_count: 1 }
    updates[:unique_protected_viewers_count] = 1 if unique_viewer_increment
    Bundle.update_counters(bundle.id, updates)
    Bundle.where(id: bundle.id).update_all(last_viewed_at: viewed_at)
  end

  private

  def register_unique_viewer(bundle:, viewer_session:, viewed_at:)
    return false if viewer_session.blank?

    BundleUniqueViewer.create!(
      bundle:,
      viewer_session:,
      first_viewed_at: viewed_at
    )
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    false
  end
end
