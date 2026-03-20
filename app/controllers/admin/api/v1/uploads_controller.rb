require "securerandom"

module Admin
  module Api
    module V1
      class UploadsController < BaseController
        before_action :mark_api_token_used!
        before_action :set_bundle_upload, only: %i[update process_upload]

        def create
          bundle_upload = BundleUpload.new(upload_params)
          bundle_upload.ingest_key = generate_ingest_key(bundle_upload)
          bundle_upload.save!

          render json: serialize_upload(bundle_upload).merge(
            upload_url: object_store.presign_put(
              key: bundle_upload.ingest_key,
              content_type: inferred_content_type(bundle_upload)
            )
          ), status: :created
        end

        def update
          @bundle_upload.update!(upload_finalize_params)
          @bundle_upload.mark_staged! unless @bundle_upload.staged?

          render json: serialize_upload(@bundle_upload)
        end

        def process_upload
          result = BundleIngestor.new(bundle_upload: @bundle_upload, object_store: object_store).call

          render json: serialize_upload(@bundle_upload).merge(
            bundle: bundle_payload(result.bundle)
          ), status: :created
        end

        private

        def set_bundle_upload
          @bundle_upload = BundleUpload.find(params[:id])
        end

        def object_store
          @object_store ||= BundleIngest::ObjectStore.new
        end

        def upload_params
          permitted = params.require(:upload).permit(
            :slug,
            :source_kind,
            :original_filename,
            :access_mode,
            :replace_existing,
            :password
          )

          permitted[:replace_existing] = ActiveModel::Type::Boolean.new.cast(permitted[:replace_existing])
          permitted[:byte_size] = 0
          permitted
        end

        def upload_finalize_params
          params.require(:upload).permit(:byte_size)
        end

        def generate_ingest_key(bundle_upload)
          token = SecureRandom.uuid
          filename = bundle_upload.original_filename.to_s.presence || "upload.bin"
          "uploads/#{token}/#{filename}"
        end

        def inferred_content_type(bundle_upload)
          Rack::Mime.mime_type(File.extname(bundle_upload.original_filename.to_s), "application/octet-stream")
        end

        def serialize_upload(bundle_upload)
          {
            id: bundle_upload.id,
            slug: bundle_upload.slug,
            source_kind: bundle_upload.source_kind,
            access_mode: bundle_upload.access_mode,
            replace_existing: bundle_upload.replace_existing,
            original_filename: bundle_upload.original_filename,
            ingest_key: bundle_upload.ingest_key,
            status: bundle_upload.status,
            byte_size: bundle_upload.byte_size
          }
        end

        def bundle_payload(bundle)
          {
            slug: bundle.slug,
            title: bundle.title,
            presentation_kind: bundle.presentation_kind,
            content_revision: bundle.content_revision,
            public_url: public_bundle_url_for(bundle)
          }
        end
      end
    end
  end
end
