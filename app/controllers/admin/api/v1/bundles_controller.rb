module Admin
  module Api
    module V1
      class BundlesController < BaseController
        before_action :mark_api_token_used!

        def availability
          slug = params[:slug].to_s
          reserved = Bundle::RESERVED_SLUGS.include?(slug)
          existing_bundle = Bundle.find_by(slug:)

          render json: {
            slug:,
            reserved:,
            available: slug.present? && !reserved && existing_bundle.blank?,
            exists: existing_bundle.present?,
            replaceable: existing_bundle.present?
          }
        end

        def show
          bundle = Bundle.find_by!(slug: params[:slug])

          render json: serialize_bundle(bundle)
        end

        private

        def serialize_bundle(bundle)
          {
            slug: bundle.slug,
            title: bundle.title,
            source_kind: bundle.source_kind,
            presentation_kind: bundle.presentation_kind,
            status: bundle.status,
            access_mode: bundle.access_mode,
            content_revision: bundle.content_revision,
            entry_path: bundle.entry_path,
            asset_count: bundle.asset_count,
            byte_size: bundle.byte_size,
            total_views_count: bundle.total_views_count,
            unique_protected_viewers_count: bundle.unique_protected_viewers_count,
            public_url: public_bundle_url_for(bundle)
          }
        end
      end
    end
  end
end
