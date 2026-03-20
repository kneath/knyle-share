module Admin
  class LoginsController < BaseController
    def show
      if admin_signed_in?
        redirect_to admin_bundles_path
      elsif !installation.claimed?
        redirect_to admin_setup_path
      end
    end
  end
end
