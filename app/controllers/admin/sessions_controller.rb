module Admin
  class SessionsController < BaseController
    # OmniAuth's own failure keys, plus the errors GitHub sends back to the
    # callback. The message comes from the query string, so anything else is
    # shown generically rather than echoed onto the login page.
    KNOWN_FAILURES = %w[
      access_denied
      application_suspended
      authenticity_error
      csrf_detected
      failed_to_connect
      invalid_credentials
      redirect_uri_mismatch
      timeout
    ].freeze

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
      message = KNOWN_FAILURES.include?(params[:message].to_s) ? params[:message].to_s.humanize : "Unknown error"
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

      destination = SafeReturnPath.call(session[:admin_return_to], fallback: admin_bundles_path)
      start_admin_session!
      redirect_to destination, notice: "Signed in as #{installation.admin_label}."
    end

    def start_admin_session!
      reset_session
      session[:admin_github_uid] = installation.admin_github_uid
      session[:admin_signed_in_at] = Time.current.to_i
    end
  end
end
