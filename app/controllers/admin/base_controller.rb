module Admin
  class BaseController < ApplicationController
    layout "admin"

    # Cookie-store sessions can't be revoked from the server, so a stolen
    # admin cookie would otherwise work until secret_key_base rotates.
    ADMIN_SESSION_LIFETIME = 14.days

    helper_method :installation, :admin_signed_in?

    private

    def installation
      @installation ||= Installation.current
    end

    def admin_signed_in?
      installation.claimed? &&
        session[:admin_github_uid] == installation.admin_github_uid &&
        Time.zone.at(session[:admin_signed_in_at].to_i) > ADMIN_SESSION_LIFETIME.ago
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
