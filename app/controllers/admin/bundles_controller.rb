module Admin
  class BundlesController < ProtectedController
    before_action :set_bundle, only: %i[show update_status update_password destroy]

    def index
      @bundles = Bundle.recent_first
    end

    def show
      @generated_password = flash[:generated_password]
    end

    def update_status
      @bundle.toggle_status!

      redirect_to admin_bundle_path(@bundle), notice: "Bundle #{@bundle.active? ? "enabled" : "disabled"}."
    end

    def update_password
      unless @bundle.protected_access?
        redirect_to admin_bundle_path(@bundle), alert: "Passwords only apply to protected bundles."
        return
      end

      new_password =
        if params[:password_strategy] == "custom"
          bundle_password_params[:password].to_s.strip
        else
          GeneratedPassword.generate
        end

      if new_password.blank?
        redirect_to admin_bundle_path(@bundle), alert: "Enter a password or generate one."
        return
      end

      @bundle.set_password!(new_password)
      flash[:generated_password] = new_password
      redirect_to admin_bundle_path(@bundle), notice: "Password replaced for #{@bundle.slug}."
    end

    def destroy
      slug = @bundle.slug
      @bundle.destroy!

      redirect_to admin_bundles_path, notice: "Deleted #{slug}."
    end

    private

    def set_bundle
      @bundle = Bundle.find_by!(slug: params[:id])
    end

    def bundle_password_params
      params.fetch(:bundle, ActionController::Parameters.new).permit(:password)
    end
  end
end
