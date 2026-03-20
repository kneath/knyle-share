class RecordPublicBundleViewJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(bundle_id:, access_method:, request_path:, viewer_session_id: nil)
    bundle = Bundle.find(bundle_id)
    viewer_session = viewer_session_id.present? ? ViewerSession.find(viewer_session_id) : nil

    PublicBundleAnalytics.new.record_view!(
      bundle:,
      viewer_session:,
      access_method:,
      request_path:
    )
  end
end
