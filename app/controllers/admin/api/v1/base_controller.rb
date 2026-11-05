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

        # Renders 403 when the token's slug prefix excludes this slug. Use it
        # only where the answer depends on the slug alone (availability and
        # create), never after a lookup, so it can't reveal what exists.
        def authorize_slug!(slug)
          return if current_api_token.permits_slug?(slug)

          render json: {
            error: "This API token can only act on bundles whose slug starts with \"#{current_api_token.slug_prefix}\"."
          }, status: :forbidden
        end

        # Scoped tokens look records up within their prefix, so anything
        # outside it raises the same not-found error as a missing record.
        # Unscoped tokens keep the default Active Record lookups.
        def find_bundle!(slug)
          return Bundle.find_by!(slug:) unless current_api_token.slug_scoped?

          current_api_token.permitted(Bundle).find_by(slug:) ||
            raise(ActiveRecord::RecordNotFound, "Bundle not found")
        end

        def find_bundle_upload!(id)
          return BundleUpload.find(id) unless current_api_token.slug_scoped?

          current_api_token.permitted(BundleUpload).find_by(id:) ||
            raise(ActiveRecord::RecordNotFound, "Upload not found")
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
          PublicBundleRouting.bundle_url(
            bundle:,
            public_host:,
            base_url: request.base_url,
            access_token:
          )
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
