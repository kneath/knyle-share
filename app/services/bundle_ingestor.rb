class BundleIngestor
  Error = Class.new(StandardError)
  Result = Data.define(:bundle, :bundle_upload, :classification, :replacing_existing)

  DEFAULT_PASSWORD_SESSION_TTL = 24.hours.to_i

  def initialize(bundle_upload:, object_store: BundleIngest::ObjectStore.new)
    @bundle_upload = bundle_upload
    @object_store = object_store
  end

  def call
    if bundle_upload.reload.ready?
      bundle = Bundle.find_by(id: bundle_upload.published_bundle_id)
      raise Error, "This upload was published, but its bundle has since been deleted." unless bundle
      return Result.new(bundle:, bundle_upload:, classification: nil, replacing_existing: bundle_upload.replace_existing?)
    end

    token = SecureRandom.uuid
    prefix = "bundles/uploads/#{bundle_upload.id}/#{token}"
    claimed = BundleUpload.where(id: bundle_upload.id, status: %w[pending staged queued failed])
      .update_all(status: "processing", processing_token: token, processing_started_at: Time.current, publish_prefix: prefix, error_message: nil)
    raise Error, "This upload is already being processed or was canceled." unless claimed == 1
    bundle_upload.reload
    copied_keys = []
    committed = false
    cleanup = nil

    # Network IO and Markdown rendering happen before acquiring a write lock.
    existing = Bundle.find_by(slug: bundle_upload.slug)
    validate_replacement!(existing)
    expected_revision = existing&.content_revision
    expected_access_revision = existing&.access_revision
    staged_entries = staged_object_lister.call
    classification = classify(staged_entries)
    copied_assets = copy_and_build_assets!(classification:, staged_entries:, copied_keys:)
    archive_key, archive_size = prepare_archive(staged_entries, copied_keys) if classification.source_kind == "directory"

    ActiveRecord::Base.transaction do
      current_upload = BundleUpload.find(bundle_upload.id)
      raise Error, "This upload was canceled or restarted." unless current_upload.processing_token == token && current_upload.processing?
      current = Bundle.find_by(slug: bundle_upload.slug)
      validate_replacement!(current)
      if current&.id != existing&.id || current&.content_revision != expected_revision || current&.access_revision != expected_access_revision
        raise Error, "This bundle changed while files were being prepared. Review it and retry."
      end
      old_keys = current ? current.assets.pluck(:storage_key) + [current.archive_storage_key] : []
      bundle = prepare_bundle!(existing_bundle: current, classification:, staged_entries:)
      bundle.update!(archive_storage_key: archive_key, archive_byte_size: archive_size)
      bundle.assets.destroy_all
      copied_assets.each { |asset| asset.bundle = bundle; asset.save! }
      bundle_upload.update!(status: "ready", published_bundle_id: bundle.id, error_message: nil)
      cleanup = StorageCleanup.schedule!(old_keys + staged_entries.map(&:source_key) + [bundle_upload.ingest_key], label: "Published #{bundle.slug}")
      @result = Result.new(bundle:, bundle_upload:, classification:, replacing_existing: existing.present?)
    end
    committed = true
    # The durable record survives a process exit; try immediately when possible.
    cleanup&.perform!(store: object_store)
    @result
  rescue StandardError => error
    unless committed
      cleanup_keys(copied_keys || [])
      BundleUpload.where(id: bundle_upload.id, processing_token: token, status: "processing")
        .update_all(status: "failed", error_message: error.message) if token
    end
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
    if existing_bundle && bundle_upload.replace_existing? &&
        ((bundle_upload.expected_content_revision && bundle_upload.expected_content_revision != existing_bundle.content_revision) ||
         (bundle_upload.expected_access_revision && bundle_upload.expected_access_revision != existing_bundle.access_revision))
      raise Error, "This bundle changed after the upload began. Start a new replacement to preserve its current settings."
    end
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
        access_revision: plan.next_access_revision,
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
        content_revision: 1,
        access_revision: 1
      )
    end
  end

  def copy_and_build_assets!(classification:, staged_entries:, copied_keys:)
    staged_entries.map do |entry|
      storage_key = "#{bundle_upload.publish_prefix}/#{entry.path}"

      copied_keys << storage_key
      transfer_entry(entry:, destination_key: storage_key)

      BundleAsset.new(
        path: entry.path,
        storage_key:,
        content_type: entry.content_type,
        byte_size: entry.byte_size,
        checksum: entry.checksum,
        rendered_html: rendered_markdown_for(entry:, classification:),
        rendered_html_version: rendered_markdown_version_for(entry:, classification:)
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
    return if keys.empty?
    cleanup = StorageCleanup.schedule!(keys, label: "Unpublished files for #{bundle_upload.slug}")
    cleanup&.perform!(store: object_store)
  end

  def prepare_archive(entries, copied_keys)
    require "rubygems/package"
    require "zlib"
    require "tempfile"
    # Use disk for the assembled archive instead of keeping another full copy
    # of the bundle in memory on small self-hosted instances.
    Tempfile.create(["knyle-bundle", ".tar"]) do |tar_io|
      tar_io.binmode
      Gem::Package::TarWriter.new(tar_io) do |tar|
        entries.each do |entry|
          body = entry.body || object_store.read(key: entry.source_key)
          tar.add_file_simple(entry.path, 0o644, body.bytesize) { |io| io.write(body) }
        end
      end
      tar_io.rewind
      Tempfile.create(["knyle-bundle", ".tar.gz"]) do |compressed|
        compressed.binmode
        gzip = Zlib::GzipWriter.new(compressed)
        IO.copy_stream(tar_io, gzip)
        gzip.finish
        compressed.flush
        compressed.rewind
        key = "#{bundle_upload.publish_prefix}-archive.tar.gz"
        copied_keys << key
        object_store.write(key:, body: compressed, content_type: "application/gzip")
        return [key, compressed.size]
      end
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

  def rendered_markdown_for(entry:, classification:)
    return unless prerender_markdown?(entry:, classification:)

    BundleMarkdownRenderer.render(markdown_body_for(entry))
  end

  def rendered_markdown_version_for(entry:, classification:)
    return unless prerender_markdown?(entry:, classification:)

    BundleMarkdownRenderer::VERSION
  end

  def prerender_markdown?(entry:, classification:)
    classification.presentation_kind == "markdown_document" &&
      classification.entry_path == entry.path &&
      entry.byte_size <= BundleStorage.inline_markdown_render_max_bytes(env: ENV)
  end

  def markdown_body_for(entry)
    return entry.body if entry.body.present?
    return object_store.read(key: entry.source_key) if entry.source_key.present?

    raise Error, "Missing markdown body for #{entry.path.inspect}"
  end
end
