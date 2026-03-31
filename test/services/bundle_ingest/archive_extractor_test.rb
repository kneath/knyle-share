require "test_helper"
require "rubygems/package"
require "zlib"

class BundleIngest::ArchiveExtractorTest < ActiveSupport::TestCase
  test "extracts files from a valid tar.gz" do
    archive = build_tar_gz(
      "index.html" => "<h1>Hello</h1>",
      "assets/app.css" => "body { color: red; }"
    )

    entries = BundleIngest::ArchiveExtractor.call(body: archive)

    assert_equal %w[assets/app.css index.html], entries.map(&:path)
    assert_equal "<h1>Hello</h1>", entries.find { |e| e.path == "index.html" }.body
  end

  test "rejects entries with path traversal via dot-dot" do
    archive = build_tar_gz("../../etc/passwd" => "root:x:0:0")

    error = assert_raises(BundleIngest::ArchiveExtractor::Error) do
      BundleIngest::ArchiveExtractor.call(body: archive)
    end

    assert_match "Path traversal", error.message
  end

  test "rejects entries with dot-dot embedded in nested paths" do
    archive = build_tar_gz("assets/../../secret.txt" => "secret")

    error = assert_raises(BundleIngest::ArchiveExtractor::Error) do
      BundleIngest::ArchiveExtractor.call(body: archive)
    end

    assert_match "Path traversal", error.message
  end

  test "strips leading slashes from absolute paths" do
    archive = build_tar_gz("/etc/hosts" => "127.0.0.1 localhost")

    entries = BundleIngest::ArchiveExtractor.call(body: archive)

    assert_equal ["etc/hosts"], entries.map(&:path)
  end

  test "strips leading dot-slash from paths" do
    archive = build_tar_gz("./README.md" => "# Hello")

    entries = BundleIngest::ArchiveExtractor.call(body: archive)

    assert_equal ["README.md"], entries.map(&:path)
  end

  test "rejects an empty archive" do
    archive = build_tar_gz({})

    error = assert_raises(BundleIngest::ArchiveExtractor::Error) do
      BundleIngest::ArchiveExtractor.call(body: archive)
    end

    assert_match "did not contain any files", error.message
  end

  test "rejects corrupt archive data" do
    error = assert_raises(BundleIngest::ArchiveExtractor::Error) do
      BundleIngest::ArchiveExtractor.call(body: "not a tar.gz at all")
    end

    assert_match "could not be processed", error.message
  end

  test "skips directory entries and only extracts files" do
    tar_io = StringIO.new
    Gem::Package::TarWriter.new(tar_io) do |tar|
      tar.mkdir("assets", 0o755)
      tar.add_file_simple("assets/app.css", 0o644, 3) { |io| io.write("hi!") }
    end
    tar_io.rewind

    gz_io = StringIO.new
    Zlib::GzipWriter.wrap(gz_io) { |gzip| gzip.write(tar_io.string) }

    entries = BundleIngest::ArchiveExtractor.call(body: gz_io.string)

    assert_equal ["assets/app.css"], entries.map(&:path)
  end

  test "infers content types from file extensions" do
    archive = build_tar_gz(
      "index.html" => "<h1>Hi</h1>",
      "app.js" => "console.log('hi')",
      "data.unknown" => "bytes"
    )

    entries = BundleIngest::ArchiveExtractor.call(body: archive)
    types = entries.map { |e| [e.path, e.content_type] }.to_h

    assert_equal "text/html", types["index.html"]
    assert_equal "text/javascript", types["app.js"]
    assert_equal "application/octet-stream", types["data.unknown"]
  end

  private

  def build_tar_gz(files)
    tar_io = StringIO.new

    Gem::Package::TarWriter.new(tar_io) do |tar|
      files.each do |path, body|
        tar.add_file_simple(path, 0o644, body.bytesize) { |io| io.write(body) }
      end
    end

    tar_io.rewind

    gz_io = StringIO.new
    Zlib::GzipWriter.wrap(gz_io) { |gzip| gzip.write(tar_io.string) }
    gz_io.string
  end
end
