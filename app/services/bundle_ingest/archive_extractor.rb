require "digest"
require "rack/mime"
require "pathname"
require "rubygems/package"
require "zlib"

module BundleIngest
  # Extracts a .tar.gz to files on disk, streaming each entry so memory stays
  # flat however large the archive is.
  class ArchiveExtractor
    class Error < StandardError; end

    MAX_ARCHIVE_BYTES = 256.megabytes
    MAX_EXTRACTED_BYTES = 256.megabytes
    MAX_FILES = 10_000
    CHUNK_SIZE = 1.megabyte

    def self.call(io:, directory:)
      new(io:, directory:).call
    end

    def initialize(io:, directory:)
      @io = io
      @directory = directory
    end

    def call
      entries = []
      total_bytes = 0

      Zlib::GzipReader.wrap(io) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            next unless entry.file?

            total_bytes += entry.header.size
            raise Error, "Archive is too large. Use at most 256 MB of extracted files." if total_bytes > MAX_EXTRACTED_BYTES
            raise Error, "Archive has too many files (maximum 10,000)." if entries.size >= MAX_FILES
            path = normalize_path(entry.full_name)
            # Name files by position, never by the archive's own paths.
            local_path = File.join(directory, "entry-#{entries.size}")
            byte_size, checksum = extract(entry, to: local_path)

            entries << StagedEntry.new(
              path:,
              source_key: nil,
              content_type: Rack::Mime.mime_type(File.extname(path), "application/octet-stream"),
              byte_size:,
              checksum:,
              local_path:
            )
          end
        end
      end

      raise Error, "Archive did not contain any files." if entries.empty?

      raise Error, "Archive contains duplicate file paths." if entries.map(&:path).uniq.size != entries.size
      entries.sort_by(&:path)
    rescue Gem::Package::TarInvalidError, Zlib::GzipFile::Error => error
      raise Error, "Uploaded archive could not be processed: #{error.message}"
    end

    private

    attr_reader :io, :directory

    def extract(entry, to:)
      digest = Digest::SHA256.new
      byte_size = 0

      File.open(to, "wb") do |file|
        while (chunk = entry.read(CHUNK_SIZE))
          digest << chunk
          byte_size += chunk.bytesize
          file.write(chunk)
        end
      end

      [byte_size, digest.hexdigest]
    end

    def normalize_path(path)
      candidate = path.to_s.sub(/\A\.\//, "").sub(/\A\//, "")
      raise Error, "Archive entry paths cannot be blank." if candidate.blank?

      normalized = Pathname.new(candidate).cleanpath.to_s
      raise Error, "Path traversal is not allowed in uploaded archives." if normalized == "." || normalized.start_with?("../")

      normalized
    end
  end
end
