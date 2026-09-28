class StorageCleanup < ApplicationRecord
  serialize :object_keys, coder: JSON
  after_create_commit :enqueue_cleanup

  def enqueue_cleanup
    StorageCleanupJob.perform_later(id)
  rescue StandardError => error
    # The persisted task is the source of truth; the worker will pick it up.
    # An unavailable queue must never roll back an already committed publish.
    Rails.logger.warn("Storage cleanup #{id} enqueue failed: #{error.class}")
  end

  def self.schedule!(keys, label:)
    keys = Array(keys).compact.uniq
    create!(object_keys: keys, label:, next_attempt_at: Time.current) if keys.any?
  end

  def perform!(store: BundleIngest::ObjectStore.new)
    claimed = self.class.where(id:).where("locked_at IS NULL OR locked_at < ?", 30.minutes.ago)
      .update_all(locked_at: Time.current)
    return unless claimed == 1

    reload.object_keys.each { |key| store.delete(key:) }
    destroy!
  rescue StandardError => error
    update!(locked_at: nil, attempts: attempts + 1, last_error: error.message,
      next_attempt_at: [2**[attempts, 10].min, 60].min.minutes.from_now)
    Rails.logger.warn("Storage cleanup #{id} failed: #{error.class}")
  end
end
