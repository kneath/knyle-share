require "pathname"

module BundleIngest
  class StagedObjectLister
    class Error < StandardError; end

    def self.call(bundle_upload:, object_store:)
      new(bundle_upload:, object_store:).call
    end

    def initialize(bundle_upload:, object_store:)
      @bundle_upload = bundle_upload
      @object_store = object_store
    end

    def call
      return archive_entries if archive_upload?

      objects = staged_objects
      raise Error, "No staged upload objects were found." if objects.empty?

      if bundle_upload.source_kind == "file" && objects.many?
        raise Error, "A file upload must stage exactly one object."
      end

      objects.map do |object|
        StagedEntry.new(
          path: relative_path_for(object.key),
          source_key: object.key,
          content_type: object.content_type,
          byte_size: object.byte_size,
          checksum: object.checksum,
          body: nil
        )
      end.sort_by(&:path)
    end

    private

    attr_reader :bundle_upload, :object_store

    def staged_objects
      prefix = bundle_upload.source_kind == "directory" ? directory_prefix : normalized_ingest_key
      objects = object_store.list(prefix:)

      return objects if bundle_upload.source_kind == "directory"

      exact_matches = objects.select { |object| object.key == normalized_ingest_key }
      exact_matches.presence || objects
    end

    def archive_upload?
      return false unless bundle_upload.source_kind == "directory"

      archive_object.present?
    end

    def archive_entries
      BundleIngest::ArchiveExtractor.call(body: object_store.read(key: archive_object.key))
    end

    def archive_object
      @archive_object ||= begin
        if object_store.list(prefix: directory_prefix).any?
          nil
        else
          object_store
            .list(prefix: normalized_ingest_key)
            .find { |object| object.key == normalized_ingest_key && archive_key?(object.key) }
        end
      end
    end

    def relative_path_for(source_key)
      path =
        if bundle_upload.source_kind == "file"
          bundle_upload.original_filename.presence || File.basename(source_key)
        else
          unless source_key.start_with?(directory_prefix)
            raise Error, "Staged object #{source_key.inspect} is outside the upload prefix."
          end

          source_key.delete_prefix(directory_prefix)
        end

      normalize_path(path)
    end

    def normalized_ingest_key
      @normalized_ingest_key ||= bundle_upload.ingest_key.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    end

    def directory_prefix
      @directory_prefix ||= "#{normalized_ingest_key}/"
    end

    def archive_key?(key)
      key.end_with?(".tar.gz", ".tgz")
    end

    def normalize_path(path)
      candidate = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      raise Error, "Staged object path cannot be blank." if candidate.blank?

      normalized = Pathname.new(candidate).cleanpath.to_s
      raise Error, "Path traversal is not allowed in staged uploads." if normalized == "." || normalized.start_with?("../")

      normalized
    end
  end
end
