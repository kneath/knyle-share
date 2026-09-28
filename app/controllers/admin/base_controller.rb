module Admin
  class BaseController < ApplicationController
    layout "admin"

    helper_method :installation, :admin_signed_in?

    private

    def installation
      @installation ||= Installation.current
    end

    def admin_signed_in?
      installation.claimed? && session[:admin_github_uid] == installation.admin_github_uid
    end

    def require_admin!
      return if admin_signed_in?

      if request.format.json?
        render json: { error: "Your session expired. Sign in again, then return here to continue." }, status: :unauthorized
        return
      end
      session[:admin_return_to] = request.fullpath if request.get?
      redirect_to(installation.claimed? ? admin_login_path : admin_setup_path)
    end
  end
end
