class PublicBundleAnalytics
  def record_view!(bundle:, access_method:, request_path:, viewer_session: nil)
    viewed_at = Time.current

    bundle.with_lock do
      unique_viewer = viewer_session.present? && !bundle.bundle_views.where(viewer_session:).exists?

      bundle.bundle_views.create!(
        viewer_session:,
        access_method:,
        request_path:,
        viewed_at:
      )

      updates = {
        total_views_count: bundle.total_views_count + 1,
        last_viewed_at: viewed_at
      }

      if unique_viewer
        updates[:unique_protected_viewers_count] = bundle.unique_protected_viewers_count + 1
      end

      bundle.update!(updates)
    end
  end
end
