module Admin
  class RootController < BaseController
    def show
      if admin_signed_in?
        redirect_to admin_bundles_path
      elsif installation.claimed?
        redirect_to admin_login_path
      else
        redirect_to admin_setup_path
      end
    end
  end
end
