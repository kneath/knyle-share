require "test_helper"
require "fileutils"
require "rubygems/package"
require "tmpdir"
require "zlib"
require_relative "../../../lib/knyle_share"

class KnyleShareUploadSourceTest < ActiveSupport::TestCase
  test "directory archives exclude unsafe files and prune excluded directories" do
    Dir.mktmpdir do |temporary_directory|
      directory = File.join(temporary_directory, "project")
      FileUtils.mkdir_p(File.join(directory, "assets"))
      File.write(File.join(directory, "index.html"), "<h1>Safe</h1>")
      File.write(File.join(directory, "assets", "app.css"), "body {}")

      excluded_files = %w[
        .git/config
        .svn/entries
        .hg/hgrc
        .env
        .env.local
        .DS_Store
        node_modules/pkg/index.js
        tmp/cache/item
        log/development.log
        .bundle/config
        vendor/bundle/gem.rb
        .terraform/state
        __pycache__/module.pyc
        secrets.pem
        private.key
        .aws/credentials
        .ssh/id_rsa
        .netrc
        .npmrc
      ]
      excluded_files.each do |relative_path|
        path = File.join(directory, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "secret")
      end

      File.symlink(
        File.join(directory, "index.html"),
        File.join(directory, "node_modules", "pkg", "index-link")
      )

      with_prepared_source(directory) do |source|
        assert_equal 2, source.file_count
        assert_equal [ "assets/app.css", "index.html" ], source.relative_paths

        archived_paths = archive_paths(source.upload_path)
        assert_equal [ "assets/app.css", "index.html" ], archived_paths
        excluded_files.each { |relative_path| assert_not_includes archived_paths, relative_path }
        assert_not_includes archived_paths, "node_modules/pkg/index-link"
      end
    end
  end

  test "project ignore patterns exclude exact paths globs and directory prefixes" do
    Dir.mktmpdir do |temporary_directory|
      directory = File.join(temporary_directory, "project")
      FileUtils.mkdir_p(File.join(directory, "nested"))
      FileUtils.mkdir_p(File.join(directory, "generated", "assets"))

      File.write(File.join(directory, "keep.txt"), "safe")
      File.write(File.join(directory, "nested", "keep.css"), "safe")
      File.write(File.join(directory, "secret.txt"), "secret")
      File.write(File.join(directory, "nested", "debug.log"), "secret")
      File.write(File.join(directory, "generated", "assets", "output.txt"), "secret")
      File.write(File.join(directory, ".knyle-shareignore"), <<~IGNORE)
        # Project-specific exclusions

        secret.txt
        *.log
        generated/
      IGNORE

      with_prepared_source(directory) do |source|
        archived_paths = archive_paths(source.upload_path)

        assert_equal [ "keep.txt", "nested/keep.css" ], archived_paths
        assert_equal archived_paths, source.relative_paths
        assert_not_includes archived_paths, "secret.txt"
        assert_not_includes archived_paths, "nested/debug.log"
        assert_not_includes archived_paths, "generated/assets/output.txt"
        assert_not_includes archived_paths, ".knyle-shareignore"
      end
    end
  end

  test "directory with only excluded files is rejected" do
    Dir.mktmpdir do |temporary_directory|
      directory = File.join(temporary_directory, "project")
      FileUtils.mkdir_p(File.join(directory, ".git"))
      File.write(File.join(directory, ".git", "config"), "secret")
      File.write(File.join(directory, ".env"), "TOKEN=secret")
      File.write(File.join(directory, ".knyle-shareignore"), "# No uploaded files\n")

      error = assert_raises(KnyleShare::Error) do
        KnyleShare::UploadSource.prepare(directory)
      end

      assert_equal "Directory #{directory.inspect} does not contain any files.", error.message
    end
  end

  private

  def with_prepared_source(path)
    source = KnyleShare::UploadSource.prepare(path)
    yield source
  ensure
    source&.cleanup
  end

  def archive_paths(path)
    paths = []

    Zlib::GzipReader.open(path) do |gzip|
      Gem::Package::TarReader.new(gzip) do |tar|
        tar.each { |entry| paths << entry.full_name }
      end
    end

    paths
  end
end
