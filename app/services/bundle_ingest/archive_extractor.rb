require "digest"
require "rack/mime"
require "pathname"
require "rubygems/package"
require "stringio"
require "zlib"

module BundleIngest
  class ArchiveExtractor
    class Error < StandardError; end

    def self.call(body:)
      new(body:).call
    end

    def initialize(body:)
      @body = body
    end

    def call
      entries = []

      Zlib::GzipReader.wrap(StringIO.new(body)) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            next unless entry.file?

            content = entry.read
            path = normalize_path(entry.full_name)

            entries << StagedEntry.new(
              path:,
              source_key: nil,
              content_type: Rack::Mime.mime_type(File.extname(path), "application/octet-stream"),
              byte_size: content.bytesize,
              checksum: Digest::SHA256.hexdigest(content),
              body: content
            )
          end
        end
      end

      raise Error, "Archive did not contain any files." if entries.empty?

      entries.sort_by(&:path)
    rescue Gem::Package::TarInvalidError, Zlib::GzipFile::Error => error
      raise Error, "Uploaded archive could not be processed: #{error.message}"
    end

    private

    attr_reader :body

    def normalize_path(path)
      candidate = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      raise Error, "Archive entry paths cannot be blank." if candidate.blank?

      normalized = Pathname.new(candidate).cleanpath.to_s
      raise Error, "Path traversal is not allowed in uploaded archives." if normalized == "." || normalized.start_with?("../")

      normalized
    end
  end
end
