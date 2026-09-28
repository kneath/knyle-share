require "securerandom"
require "aws-sdk-s3"

module Admin
  class UploadsController < ProtectedController
    before_action :set_bundle_upload, only: %i[show update transfer process_upload destroy]
    rescue_from ActiveRecord::RecordInvalid, with: :validation_error
    rescue_from Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError, with: :storage_error

    def new
      @replacement = Bundle.find_by!(slug: params[:replace]) if params[:replace].present?
    end

    def availability
      slug = params[:slug].to_s
      existing = Bundle.find_by(slug:)
      valid = Bundle.valid_slug?(slug) && !Bundle::RESERVED_SLUGS.include?(slug)
      render json: { valid:, available: valid && existing.nil?, exists: existing.present? }
    end

    def create
      upload = BundleUpload.new(upload_params)
      existing = Bundle.find_by(slug: upload.slug)
      if existing && !upload.replace_existing?
        return render json: { error: "That link address is already in use. Choose another address or replace the existing bundle." }, status: :conflict
      end
      if upload.replace_existing? && !existing
        return render json: { error: "The bundle to replace no longer exists." }, status: :conflict
      end
      if upload.replace_existing? && existing
        upload.expected_content_revision = existing.content_revision
        upload.expected_access_revision = existing.access_revision
      end
      if existing&.protected_access? && upload.protected_access? && params[:preserve_password] == "true"
        upload.password_digest = existing.password_digest
      end
      upload.ingest_key = "uploads/#{SecureRandom.uuid}/#{File.basename(upload.original_filename.to_s.presence || 'upload.bin')}"
      upload.save!
      if params[:file]
        stage_file(upload, params[:file])
        render json: payload(upload), status: :created
      else
        render json: payload(upload).merge(upload_url: object_store.presign_put(key: upload.ingest_key, content_type: inferred_content_type(upload)),
          content_type: inferred_content_type(upload)), status: :created
      end
    end

    def show
      response.set_header("Cache-Control", "no-store")
      render json: payload(@bundle_upload)
    end

    def update
      return render json: payload(@bundle_upload) if @bundle_upload.staged? || @bundle_upload.ready?
      unless @bundle_upload.pending?
        return render json: { error: "This upload cannot receive more files." }, status: :conflict
      end
      @bundle_upload.update!(byte_size: params[:byte_size])
      @bundle_upload.mark_staged!
      render json: payload(@bundle_upload)
    end

    # Same-origin fallback for installations without S3 browser-upload CORS.
    def transfer
      unless @bundle_upload.pending?
        return render json: { error: "This upload cannot receive more files." }, status: :conflict
      end
      return render json: { error: "Choose a file to upload." }, status: :unprocessable_entity unless params[:file]
      stage_file(@bundle_upload, params[:file])
      render json: payload(@bundle_upload)
    end

    def process_upload
      changed = BundleUpload.where(id: @bundle_upload.id, status: %w[staged failed]).update_all(status: "queued", error_message: nil, updated_at: Time.current)
      ProcessBundleUploadJob.perform_later(@bundle_upload.id) if changed == 1
      @bundle_upload.reload
      unless %w[queued processing ready].include?(@bundle_upload.status)
        return render json: { error: "Finish transferring the file before publishing." }, status: :conflict
      end
      render json: payload(@bundle_upload), status: :accepted
    end

    def destroy
      changed = BundleUpload.where(id: @bundle_upload.id).where.not(status: "ready")
        .update_all(status: "canceled", processing_token: nil, updated_at: Time.current)
      if changed == 1
        StorageCleanup.schedule!([@bundle_upload.ingest_key], label: "Canceled #{@bundle_upload.slug}")
      end
      render json: payload(@bundle_upload.reload)
    end

    private

    def set_bundle_upload
      @bundle_upload = BundleUpload.find(params[:id])
    end

    def object_store
      @object_store ||= BundleIngest::ObjectStore.new
    end

    def upload_params
      permitted = params.permit(:slug, :source_kind, :original_filename, :access_mode, :replace_existing, :password)
      permitted[:replace_existing] = ActiveModel::Type::Boolean.new.cast(permitted[:replace_existing])
      permitted[:byte_size] = 0
      permitted
    end

    def inferred_content_type(upload)
      Rack::Mime.mime_type(File.extname(upload.original_filename.to_s).downcase, "application/octet-stream")
    end

    def stage_file(upload, file)
      upload.update!(byte_size: file.size)
      object_store.write(key: upload.ingest_key, body: file.tempfile, content_type: inferred_content_type(upload))
      upload.mark_staged!
    end

    def payload(upload)
      bundle = Bundle.find_by(id: upload.published_bundle_id) if upload.ready?
      { id: upload.id, slug: upload.slug, status: upload.status, error: upload.error_message,
        bundle_slug: bundle&.slug, public_url: bundle && public_bundle_url_for(bundle) }
    end

    def validation_error(error)
      render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end

    def storage_error(error)
      Rails.logger.warn("Upload storage request failed: #{error.class}")
      render json: { error: "Storage is temporarily unavailable. Your file selection is still here; please retry." }, status: :service_unavailable
    end
  end
end
