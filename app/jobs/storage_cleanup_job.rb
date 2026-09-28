class StorageCleanupJob < ApplicationJob
  def perform(id)
    StorageCleanup.find_by(id:)&.perform!
  end
end
