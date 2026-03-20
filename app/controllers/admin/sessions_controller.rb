module Admin
  class SessionsController < BaseController
    def create
      auth = request.env["omniauth.auth"]

      if auth.blank?
        redirect_to admin_login_path, alert: "GitHub did not return account information."
        return
      end

      if installation.claimed?
        sign_in_existing_admin(auth)
      else
        claim_admin(auth)
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: "You have been signed out."
    end

    def failure
      message = params[:message].to_s.humanize.presence || "Unknown error"
      redirect_to(installation.claimed? ? admin_login_path : admin_setup_path, alert: "GitHub sign-in failed: #{message}")
    end

    private

    def claim_admin(auth)
      validation = SetupValidation.new.call

      unless validation.passed?
        redirect_to admin_setup_path, alert: "Setup validation must pass before the admin account can be claimed."
        return
      end

      installation.claim_from_auth!(auth)
      start_admin_session!
      redirect_to admin_bundles_path, notice: "Admin account claimed for #{installation.admin_label}."
    end

    def sign_in_existing_admin(auth)
      unless installation.admin_matches?(auth)
        reset_session
        redirect_to admin_login_path, alert: "This GitHub account is not the configured admin."
        return
      end

      start_admin_session!
      redirect_to admin_bundles_path, notice: "Signed in as #{installation.admin_label}."
    end

    def start_admin_session!
      reset_session
      session[:admin_github_uid] = installation.admin_github_uid
    end
  end
end
