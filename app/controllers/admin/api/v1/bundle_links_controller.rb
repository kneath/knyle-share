module Admin
  module Api
    module V1
      class BundleLinksController < BaseController
        before_action :mark_api_token_used!

        def create
          bundle = Bundle.find_by!(slug: params[:slug])
          raise ActiveRecord::RecordNotFound, "Bundle not found" unless bundle.protected_access?

          preset = BundleAccessLink::PRESETS[params[:expires_in].to_s]
          unless preset
            render json: { error: "Invalid expiration preset." }, status: :unprocessable_entity
            return
          end

          token = BundleAccessLink.generate(bundle:, expires_in: preset.fetch(:duration))

          render json: {
            slug: bundle.slug,
            expires_in: params[:expires_in].to_s,
            expires_at: (Time.current + preset.fetch(:duration)).iso8601,
            url: public_bundle_url_for(bundle, access_token: token)
          }, status: :created
        end
      end
    end
  end
end
