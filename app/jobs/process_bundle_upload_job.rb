class ProcessBundleUploadJob < ApplicationJob
  def perform(id)
    upload = BundleUpload.find_by(id:)
    return unless upload&.status == "queued"

    BundleIngestor.new(bundle_upload: upload).call
  rescue BundleIngestor::Error => error
    Rails.logger.warn("Upload #{id} failed: #{error.class}")
  end
end
