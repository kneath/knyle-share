class PublishingMaintenance
  def self.run
    BundleUpload.where(status: "processing").where("processing_started_at < ?", 30.minutes.ago).find_each do |upload|
      token = upload.processing_token
      if BundleUpload.where(id: upload.id, processing_token: token, status: "processing")
          .update_all(status: "failed", processing_token: nil, error_message: "Processing was interrupted. Retry to finish publishing.") == 1
        store = BundleIngest::ObjectStore.new
        keys = store.list(prefix: upload.publish_prefix.to_s).map(&:key) if upload.publish_prefix.present?
        StorageCleanup.schedule!(keys, label: "Interrupted upload #{upload.slug}")
      end
    end
    BundleUpload.where(status: "queued").find_each { |upload| ProcessBundleUploadJob.perform_now(upload.id) }
    BundleUpload.where(status: %w[pending staged failed canceled]).where("updated_at < ?", 7.days.ago).find_each do |upload|
      store = BundleIngest::ObjectStore.new
      keys = store.list(prefix: upload.ingest_key).map(&:key)
      keys.concat(store.list(prefix: upload.publish_prefix).map(&:key)) if upload.publish_prefix.present?
      BundleUpload.transaction do
        StorageCleanup.schedule!(keys, label: "Expired upload #{upload.slug}")
        upload.destroy!
      end
    end
    StorageCleanup.where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current).find_each(&:perform!)
  end
end
