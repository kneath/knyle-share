# Anonymous traffic adds a BundleView per page view and a ViewerSession per
# signed-link visit without a cookie, and nothing read them back, so scripted
# requests could fill the disk. Prune both. The counters on bundles are kept,
# so view and unique-viewer counts don't change.
class ViewerDataPruner
  VIEW_RETENTION = 90.days
  # Expired sessions are already useless for access; the grace period leaves
  # time for view jobs queued just before expiry.
  EXPIRED_SESSION_GRACE = 1.day
  BATCH_SIZE = 1_000

  def self.run(now: Time.current)
    new(now:).run
  end

  def initialize(now:)
    @now = now
  end

  def run
    prune_views
    prune_expired_sessions
  end

  private

  attr_reader :now

  def prune_views
    BundleView.where(viewed_at: ...(now - VIEW_RETENTION)).in_batches(of: BATCH_SIZE).delete_all
  end

  # Unique-viewer rows only dedupe views within a live session. A returning
  # viewer gets a new session (and counts again) either way.
  def prune_expired_sessions
    ViewerSession.where(expires_at: ...(now - EXPIRED_SESSION_GRACE)).in_batches(of: BATCH_SIZE) do |sessions|
      ids = sessions.ids
      ViewerSession.transaction do
        BundleUniqueViewer.where(viewer_session_id: ids).delete_all
        BundleView.where(viewer_session_id: ids).update_all(viewer_session_id: nil)
        ViewerSession.where(id: ids).delete_all
      end
    end
  end
end
