require "securerandom"

module Admin
  module Api
    module V1
      class UploadsController < BaseController
        before_action :mark_api_token_used!
        before_action :set_bundle_upload, only: %i[show update process_upload]
        before_action -> { authorize_slug!(params.dig(:upload, :slug)) }, only: :create

        def create
          bundle_upload = BundleUpload.new(upload_params)
          bundle_upload.ingest_key = generate_ingest_key(bundle_upload)
          if bundle_upload.replace_existing? && (existing = Bundle.find_by(slug: bundle_upload.slug))
            bundle_upload.expected_content_revision = existing.content_revision
            bundle_upload.expected_access_revision = existing.access_revision
          end
          unless bundle_upload.save
            return render json: {
              error: bundle_upload.errors.full_messages.to_sentence
            }, status: :unprocessable_entity
          end

          render json: serialize_upload(bundle_upload).merge(
            upload_url: object_store.presign_put(
              key: bundle_upload.ingest_key,
              content_type: inferred_content_type(bundle_upload)
            )
          ), status: :created
        end

        # Publishing status, for clients that asked to publish in the background.
        def show
          response.set_header("Cache-Control", "no-store")
          render json: status_payload(@bundle_upload)
        end

        def update
          return render json: serialize_upload(@bundle_upload) if @bundle_upload.ready? || @bundle_upload.staged?
          unless @bundle_upload.pending?
            return render json: { error: "This upload cannot be finalized in its current state." }, status: :conflict
          end
          @bundle_upload.update!(upload_finalize_params)
          @bundle_upload.mark_staged! unless @bundle_upload.staged?

          render json: serialize_upload(@bundle_upload)
        end

        # Clients that send "Prefer: respond-async" get 202 right away, and the
        # publishing worker does the work. They poll GET /api/v1/uploads/:id.
        # Clients that don't (older CLIs) still publish within this request.
        def process_upload
          return queue_upload if respond_async?

          result = BundleIngestor.new(bundle_upload: @bundle_upload, object_store: object_store).call

          render json: serialize_upload(@bundle_upload).merge(
            bundle: bundle_payload(result.bundle)
          ), status: :created
        end

        private

        def respond_async?
          request.headers["Prefer"].to_s.split(",").any? { |preference| preference.strip.casecmp?("respond-async") }
        end

        def queue_upload
          BundleUpload.where(id: @bundle_upload.id, status: %w[pending staged failed])
            .update_all(status: "queued", error_message: nil, updated_at: Time.current)
          @bundle_upload.reload
          unless %w[queued processing ready].include?(@bundle_upload.status)
            return render json: { error: "This upload cannot be published in its current state." }, status: :conflict
          end

          response.set_header("Preference-Applied", "respond-async")
          render json: status_payload(@bundle_upload), status: @bundle_upload.ready? ? :created : :accepted
        end

        def status_payload(bundle_upload)
          payload = serialize_upload(bundle_upload)
          payload[:error_message] = bundle_upload.error_message if bundle_upload.status == "failed"
          if bundle_upload.ready?
            if (bundle = Bundle.find_by(id: bundle_upload.published_bundle_id))
              payload[:bundle] = bundle_payload(bundle)
            else
              payload[:error_message] = "This upload was published, but its bundle has since been deleted."
            end
          end
          payload
        end

        def set_bundle_upload
          @bundle_upload = find_bundle_upload!(params[:id])
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
          # The model rejects paths and control characters before saving. Avoid
          # File.basename here so null bytes reach validation instead of raising.
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
