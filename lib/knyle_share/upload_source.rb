require "find"
require "pathname"
require "rack/mime"
require "rubygems/package"
require "tempfile"
require "zlib"

module KnyleShare
  class UploadSource
    attr_reader :input_path, :upload_path, :source_kind, :original_filename, :content_type

    def self.prepare(input_path)
      new(input_path).prepare
    end

    def initialize(input_path)
      @input_path = File.expand_path(input_path.to_s)
      @tempfiles = []
    end

    def prepare
      raise Error, "Path #{input_path.inspect} does not exist." unless File.exist?(input_path)

      if File.directory?(input_path)
        prepare_directory
      else
        prepare_file
      end

      self
    end

    def byte_size
      File.size(upload_path)
    end

    def cleanup
      tempfiles.each(&:close!)
    end

    def display_path
      input_path
    end

    private

    attr_reader :tempfiles
    attr_writer :upload_path, :source_kind, :original_filename, :content_type

    def prepare_file
      self.upload_path = input_path
      self.source_kind = "file"
      self.original_filename = File.basename(input_path)
      self.content_type = Rack::Mime.mime_type(File.extname(original_filename), "application/octet-stream")
    end

    def prepare_directory
      archive = build_archive
      self.upload_path = archive.path
      self.source_kind = "directory"
      self.original_filename = "#{directory_name}.tar.gz"
      self.content_type = Rack::Mime.mime_type(File.extname(original_filename), "application/octet-stream")
      tempfiles << archive
    end

    def build_archive
      tarfile = Tempfile.new([ directory_name, ".tar" ])
      tarfile.binmode

      file_count = 0

      Gem::Package::TarWriter.new(tarfile) do |tar|
        Find.find(input_path) do |entry_path|
          relative_path = relative_entry_path(entry_path)
          next if relative_path.nil?

          stat = File.lstat(entry_path)
          raise Error, "Symlinks are not supported in directory uploads." if stat.symlink?
          next if stat.directory?

          tar.add_file_simple(relative_path, stat.mode, stat.size) do |archive_file|
            File.open(entry_path, "rb") do |source|
              IO.copy_stream(source, archive_file)
            end
          end

          file_count += 1
        end
      end

      raise Error, "Directory #{input_path.inspect} does not contain any files." if file_count.zero?

      tarfile.rewind
      gzfile = Tempfile.new([ directory_name, ".tar.gz" ])
      gzfile.close

      Zlib::GzipWriter.open(gzfile.path) do |gzip|
        File.open(tarfile.path, "rb") do |tar_source|
          IO.copy_stream(tar_source, gzip)
        end
      end

      gzfile.open
      gzfile.binmode
      gzfile.rewind
      tarfile.close!
      gzfile
    end

    def relative_entry_path(entry_path)
      return nil if entry_path == input_path

      Pathname.new(entry_path).relative_path_from(Pathname.new(input_path)).to_s
    end

    def directory_name
      File.basename(input_path)
    end
  end
end
