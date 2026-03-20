module BundleIngest
  class Classifier
    MARKDOWN_EXTENSIONS = %w[.md .markdown].freeze

    def self.call(source_kind:, entries:)
      new(source_kind:, entries:).call
    end

    def initialize(source_kind:, entries:)
      @source_kind = source_kind.to_s
      @entries = Array(entries)
    end

    def call
      raise ClassificationError, "No uploaded files were provided." if paths.empty?

      case source_kind
      when "directory"
        classify_directory
      when "file"
        classify_file
      else
        raise ClassificationError, "Unknown source kind: #{source_kind}"
      end
    end

    private

    attr_reader :source_kind, :entries

    def classify_directory
      if paths.include?("index.html")
        Classification.new(
          presentation_kind: "static_site",
          source_kind: "directory",
          entry_path: "index.html",
          paths:
        )
      else
        Classification.new(
          presentation_kind: "file_listing",
          source_kind: "directory",
          entry_path: nil,
          paths:
        )
      end
    end

    def classify_file
      entry = paths.one? ? paths.first : raise(ClassificationError, "A file upload must contain exactly one file.")
      extension = File.extname(entry).downcase

      if MARKDOWN_EXTENSIONS.include?(extension)
        Classification.new(
          presentation_kind: "markdown_document",
          source_kind: "file",
          entry_path: entry,
          paths:
        )
      else
        Classification.new(
          presentation_kind: "single_download",
          source_kind: "file",
          entry_path: entry,
          paths:
        )
      end
    end

    def paths
      @paths ||= entries.map { |entry| extract_path(entry) }.compact.map { |path| normalize_path(path) }
    end

    def extract_path(entry)
      case entry
      when String
        entry
      when Hash
        entry[:path] || entry["path"] || entry[:name] || entry["name"]
      else
        entry.respond_to?(:path) ? entry.path : nil
      end
    end

    def normalize_path(path)
      normalized = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      Pathname.new(normalized).cleanpath.to_s
    end
  end
end
