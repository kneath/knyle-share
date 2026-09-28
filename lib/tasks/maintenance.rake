namespace :maintenance do
  desc "Recover queued uploads, retry storage deletion, and clean abandoned uploads"
  task run: :environment do
    PublishingMaintenance.run
  end
end
