module Admin
  module Api
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_api_token!

        rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
        rescue_from BundleIngestor::Error, with: :render_unprocessable_entity
        rescue_from BundleIngest::ClassificationError, with: :render_unprocessable_entity
        rescue_from BundleIngest::StagedObjectLister::Error, with: :render_unprocessable_entity
        rescue_from BundleIngest::ArchiveExtractor::Error, with: :render_unprocessable_entity

        private

        attr_reader :current_api_token

        def authenticate_api_token!
          @current_api_token = ApiToken.authenticate(bearer_token)
          return if @current_api_token.present?

          render json: { error: "Unauthorized" }, status: :unauthorized
        end

        def mark_api_token_used!
          current_api_token&.update_column(:last_used_at, Time.current)
        end

        def bearer_token
          authorization = request.authorization.to_s
          scheme, token = authorization.split(" ", 2)
          return unless scheme&.casecmp("Bearer")&.zero?

          token
        end

        def admin_host
          ENV.fetch("ADMIN_HOST", "admin.lvh.me")
        end

        def public_host
          ENV.fetch("PUBLIC_HOST", "share.lvh.me")
        end

        def public_bundle_url_for(bundle, access_token: nil)
          uri = URI::Generic.build(scheme: request.protocol.delete_suffix("://"), host: public_host, path: "/#{bundle.slug}")
          uri.query = access_token.present? ? { access: access_token }.to_query : nil
          uri.to_s
        end

        def render_not_found(error)
          render json: { error: error.message }, status: :not_found
        end

        def render_unprocessable_entity(error)
          render json: { error: error.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
