require "securerandom"

module Admin
  class UploadsController < ProtectedController
    before_action :set_bundle_upload, only: %i[process_upload]

    def new
    end

    def create
      bundle_upload = BundleUpload.new(upload_params)
      bundle_upload.ingest_key = generate_ingest_key(bundle_upload)
      bundle_upload.save!

      file = params[:file]
      content_type = file.content_type.presence || inferred_content_type(bundle_upload)

      object_store.write(
        key: bundle_upload.ingest_key,
        body: file.tempfile,
        content_type:
      )

      bundle_upload.update!(byte_size: file.size)
      bundle_upload.mark_staged!

      render json: { id: bundle_upload.id, slug: bundle_upload.slug }, status: :created
    end

    def process_upload
      result = BundleIngestor.new(bundle_upload: @bundle_upload, object_store:).call

      render json: {
        id: @bundle_upload.id,
        status: @bundle_upload.status,
        bundle_slug: result.bundle.slug
      }, status: :created
    rescue BundleIngestor::Error,
           BundleIngest::ClassificationError,
           BundleIngest::StagedObjectLister::Error,
           BundleIngest::ArchiveExtractor::Error => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def set_bundle_upload
      @bundle_upload = BundleUpload.find(params[:id])
    end

    def object_store
      @object_store ||= BundleIngest::ObjectStore.new
    end

    def upload_params
      permitted = params.permit(
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

    def generate_ingest_key(bundle_upload)
      token = SecureRandom.uuid
      filename = bundle_upload.original_filename.to_s.presence || "upload.bin"
      "uploads/#{token}/#{filename}"
    end

    def inferred_content_type(bundle_upload)
      Rack::Mime.mime_type(File.extname(bundle_upload.original_filename.to_s), "application/octet-stream")
    end
  end
end
