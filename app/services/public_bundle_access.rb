class PublicBundleAccess
  Result = Data.define(:allowed?, :access_method, :viewer_session, :message)

  def initialize(bundle:, cookies:, params:)
    @bundle = bundle
    @cookies = cookies
    @params = params
  end

  def call
    return Result.new(allowed?: true, access_method: "public", viewer_session: nil, message: nil) if bundle.public_access?

    viewer_session = viewer_session_manager.find(bundle:)
    if viewer_session.present?
      return Result.new(allowed?: true, access_method: "password_session", viewer_session:, message: nil)
    end

    if params[:access].present?
      payload = BundleAccessLink.verify(params[:access])
      if payload.present? &&
        payload[:bundle_id] == bundle.id &&
        payload[:slug] == bundle.slug &&
        payload[:access_revision] == bundle.access_revision
        viewer_session = viewer_session_manager.establish!(bundle:, expires_at: payload[:expires_at])
        return Result.new(allowed?: true, access_method: "signed_link", viewer_session:, message: nil)
      end

      return Result.new(allowed?: false, access_method: nil, viewer_session: nil, message: "This expiring link is invalid or has expired.")
    end

    Result.new(allowed?: false, access_method: nil, viewer_session: nil, message: nil)
  end

  private

  attr_reader :bundle, :cookies, :params

  def viewer_session_manager
    @viewer_session_manager ||= PublicViewerSessionManager.new(cookies:)
  end
end
