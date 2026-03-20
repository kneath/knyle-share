module Admin
  class BundleLinksController < ProtectedController
    before_action :set_bundle
    before_action :ensure_protected_bundle

    def new
      @expiration_presets = BundleAccessLink::PRESETS
      @selected_preset = "1_week"
    end

    def create
      @expiration_presets = BundleAccessLink::PRESETS
      @selected_preset = params[:expires_in].to_s
      preset = @expiration_presets[@selected_preset]

      if preset.blank?
        @selected_preset = "1_week"
        flash.now[:alert] = "Choose a valid expiration."
        render :new, status: :unprocessable_entity
        return
      end

      @expires_at = Time.current + preset.fetch(:duration)
      token = BundleAccessLink.generate(bundle: @bundle, expires_in: preset.fetch(:duration))
      @generated_link = public_bundle_url_for(@bundle, access_token: token)

      render :new
    end

    private

    def set_bundle
      @bundle = Bundle.find_by!(slug: params[:bundle_id])
    end

    def ensure_protected_bundle
      return if @bundle.protected_access?

      redirect_to admin_bundle_path(@bundle), alert: "Signed links only apply to protected bundles."
    end
  end
end
