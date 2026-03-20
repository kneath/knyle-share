module Public
  class AccessController < BaseController
    before_action :set_bundle

    def create
      unless ensure_bundle_is_available!
        return
      end

      if @bundle.public_access?
        redirect_to public_bundle_path(slug: @bundle.slug)
        return
      end

      unless @bundle.authenticate(params[:password].to_s)
        @access_message = "Password was incorrect."
        render "public/bundles/protected", status: :unprocessable_entity
        return
      end

      session = viewer_session_manager.find(bundle: @bundle)

      if session.present?
        viewer_session_manager.refresh!(bundle: @bundle, viewer_session: session)
      else
        viewer_session_manager.establish!(bundle: @bundle)
      end

      redirect_to public_bundle_path(slug: @bundle.slug), notice: "Access granted."
    end
  end
end
