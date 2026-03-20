class BundleIngestor
  Error = Class.new(StandardError)
  Result = Data.define(:bundle, :bundle_upload, :classification, :replacing_existing)

  DEFAULT_PASSWORD_SESSION_TTL = 24.hours.to_i

  def initialize(bundle_upload:, object_store: BundleIngest::ObjectStore.new)
    @bundle_upload = bundle_upload
    @object_store = object_store
  end

  def call
    copied_keys = []
    staged_entries = []
    old_keys = []
    result = nil

    bundle_upload.mark_processing! unless bundle_upload.processing?

    ActiveRecord::Base.transaction do
      staged_entries = staged_object_lister.call
      classification = classify(staged_entries)
      existing_bundle = Bundle.lock.find_by(slug: bundle_upload.slug)

      validate_replacement!(existing_bundle)

      bundle = prepare_bundle!(
        existing_bundle:,
        classification:,
        staged_entries:
      )

      copied_assets = copy_and_build_assets!(bundle:, staged_entries:, copied_keys:)
      old_keys = existing_bundle.present? ? existing_bundle.assets.pluck(:storage_key) : []

      bundle.assets.destroy_all
      copied_assets.each(&:save!)

      bundle_upload.mark_ready!

      result = Result.new(
        bundle:,
        bundle_upload:,
        classification:,
        replacing_existing: existing_bundle.present?
      )
    end

    cleanup_keys(staged_entries.map(&:source_key))
    cleanup_keys(old_keys)

    result
  rescue StandardError => error
    cleanup_keys(copied_keys)
    bundle_upload.mark_failed!(error.message) if bundle_upload.persisted?
    raise Error, error.message
  end

  private

  attr_reader :bundle_upload, :object_store

  def staged_object_lister
    @staged_object_lister ||= BundleIngest::StagedObjectLister.new(
      bundle_upload:,
      object_store:
    )
  end

  def classify(staged_entries)
    BundleIngest::Classifier.call(
      source_kind: bundle_upload.source_kind,
      entries: staged_entries.map { |entry| { path: entry.path } }
    )
  end

  def validate_replacement!(existing_bundle)
    if existing_bundle.present? && !bundle_upload.replace_existing?
      raise Error, "Bundle slug #{bundle_upload.slug.inspect} already exists."
    end

    if existing_bundle.blank? && bundle_upload.replace_existing?
      raise Error, "No existing bundle was found for replacement."
    end
  end

  def prepare_bundle!(existing_bundle:, classification:, staged_entries:)
    if existing_bundle.present?
      plan = BundleIngest::ReplacementPlanner.call(bundle: existing_bundle, replace_existing: true)

      existing_bundle.update!(
        source_kind: classification.source_kind,
        presentation_kind: classification.presentation_kind,
        access_mode: bundle_upload.access_mode,
        password_digest: protected_password_digest,
        entry_path: classification.entry_path,
        byte_size: staged_entries.sum(&:byte_size),
        content_revision: plan.next_content_revision,
        last_replaced_at: Time.current
      )

      existing_bundle
    else
      Bundle.create!(
        slug: bundle_upload.slug,
        title: default_title,
        source_kind: classification.source_kind,
        presentation_kind: classification.presentation_kind,
        status: "active",
        access_mode: bundle_upload.access_mode,
        password_digest: protected_password_digest,
        password_session_ttl_seconds: DEFAULT_PASSWORD_SESSION_TTL,
        entry_path: classification.entry_path,
        byte_size: staged_entries.sum(&:byte_size),
        content_revision: 1
      )
    end
  end

  def copy_and_build_assets!(bundle:, staged_entries:, copied_keys:)
    staged_entries.map do |entry|
      storage_key = BundleIngest::PublishedStorageKey.call(
        bundle_id: bundle.id,
        content_revision: bundle.content_revision,
        path: entry.path
      )

      transfer_entry(entry:, destination_key: storage_key)
      copied_keys << storage_key

      BundleAsset.new(
        bundle:,
        path: entry.path,
        storage_key:,
        content_type: entry.content_type,
        byte_size: entry.byte_size,
        checksum: entry.checksum
      )
    end
  end

  def protected_password_digest
    return nil if bundle_upload.public_access?

    bundle_upload.password_digest
  end

  def default_title
    bundle_upload.slug.tr("-", " ").titleize
  end

  def cleanup_keys(keys)
    Array(keys).each do |key|
      object_store.delete(key:)
    rescue StandardError => error
      Rails.logger.warn("BundleIngestor cleanup failed for #{key}: #{error.message}")
    end
  end

  def transfer_entry(entry:, destination_key:)
    if entry.source_key.present?
      object_store.copy(source_key: entry.source_key, destination_key:)
    else
      object_store.write(
        key: destination_key,
        body: entry.body,
        content_type: entry.content_type
      )
    end
  end
end
