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

      redirect_to(installation.claimed? ? admin_login_path : admin_setup_path)
    end
  end
end
