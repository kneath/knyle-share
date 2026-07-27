require "find"
require "pathname"
require "rack/mime"
require "rubygems/package"
require "tempfile"
require "zlib"

module KnyleShare
  class UploadSource
    EXCLUDED_DIRECTORY_NAMES = %w[
      .git
      .svn
      .hg
      node_modules
      tmp
      log
      .bundle
      .terraform
      __pycache__
      .aws
      .ssh
    ].freeze
    EXCLUDED_FILE_NAMES = %w[
      .DS_Store
      .netrc
      .npmrc
      .knyle-shareignore
    ].freeze
    EXCLUDED_FILE_PATTERNS = %w[
      .env
      .env.*
      *.pem
      *.key
    ].freeze
    FNMATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

    attr_reader :input_path, :upload_path, :source_kind, :original_filename, :content_type, :file_count, :relative_paths

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
    attr_writer :upload_path, :source_kind, :original_filename, :content_type, :file_count, :relative_paths

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

      included_paths = []
      ignore_patterns = load_ignore_patterns

      Gem::Package::TarWriter.new(tarfile) do |tar|
        Find.find(input_path) do |entry_path|
          relative_path = relative_entry_path(entry_path)
          next if relative_path.nil?

          if excluded?(entry_path, relative_path, ignore_patterns)
            Find.prune if File.directory?(entry_path)
            next
          end

          stat = File.lstat(entry_path)
          raise Error, "Symlinks are not supported in directory uploads." if stat.symlink?
          next if stat.directory?

          tar.add_file_simple(relative_path, stat.mode, stat.size) do |archive_file|
            File.open(entry_path, "rb") do |source|
              IO.copy_stream(source, archive_file)
            end
          end

          included_paths << relative_path
        end
      end

      raise Error, "Directory #{input_path.inspect} does not contain any files." if included_paths.empty?

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
      self.relative_paths = included_paths.freeze
      self.file_count = included_paths.length
      gzfile
    end

    def load_ignore_patterns
      ignore_path = File.join(input_path, ".knyle-shareignore")
      return [] unless File.file?(ignore_path)

      # Patterns match archive-relative paths; basename globs and trailing-slash directory prefixes are also supported.
      File.readlines(ignore_path, chomp: true).filter_map do |line|
        pattern = line.strip
        pattern unless pattern.empty? || pattern.start_with?("#")
      end
    end

    def excluded?(entry_path, relative_path, ignore_patterns)
      default_excluded?(relative_path) || ignore_patterns.any? do |pattern|
        ignore_pattern_matches?(pattern, entry_path, relative_path)
      end
    end

    def default_excluded?(relative_path)
      path_parts = relative_path.split(File::SEPARATOR)
      basename = path_parts.last

      EXCLUDED_DIRECTORY_NAMES.include?(basename) ||
        EXCLUDED_FILE_NAMES.include?(basename) ||
        EXCLUDED_FILE_PATTERNS.any? { |pattern| File.fnmatch?(pattern, basename, FNMATCH_FLAGS) } ||
        path_parts.each_cons(2).any? { |parent, child| parent == "vendor" && child == "bundle" }
    end

    def ignore_pattern_matches?(pattern, entry_path, relative_path)
      if pattern.end_with?("/")
        directory_prefix = pattern.delete_suffix("/")
        return relative_path == directory_prefix || relative_path.start_with?("#{directory_prefix}/")
      end

      File.fnmatch?(pattern, relative_path, FNMATCH_FLAGS) ||
        File.fnmatch?(pattern, File.basename(entry_path), FNMATCH_FLAGS)
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
