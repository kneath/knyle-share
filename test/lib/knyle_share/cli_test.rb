require "test_helper"
require "stringio"
require "tempfile"
require_relative "../../../lib/knyle_share/cli"

class KnyleShareCliTest < ActiveSupport::TestCase
  test "defines the Zeitwerk-compatible cli constant" do
    assert_equal KnyleShare::Cli, KnyleShare::CLI
  end

  test "resolved public access with a link expiration fails before preparing or uploading" do
    stdout = StringIO.new
    stderr = StringIO.new
    config_store = Struct.new(:load).new(
      {
        admin_url: "http://admin.example.test",
        api_token: "secret"
      }
    )
    cli = KnyleShare::Cli.new(
      stdin: StringIO.new,
      stdout:,
      stderr:,
      env: {},
      config_store:
    )

    Tempfile.create("knyle-share-cli-test") do |file|
      KnyleShare::Client.stub :new, Object.new do
        cli.stub :resolve_access_mode, "public" do
          status = cli.run([ file.path, "--link-expiration", "1_week" ])

          assert_equal 1, status
        end
      end
    end

    assert_equal "", stdout.string
    assert_includes stderr.string, "Expiring links only apply to protected bundles"
  end

  test "files over 5 GB are refused before creating an upload" do
    stdout = StringIO.new
    stderr = StringIO.new
    config_store = Struct.new(:load).new({ admin_url: "http://admin.example.test", api_token: "secret" })
    cli = KnyleShare::Cli.new(stdin: StringIO.new, stdout:, stderr:, env: {}, config_store:)
    client = Object.new
    client.define_singleton_method(:availability) { |slug:| { "valid" => true, "available" => true, "exists" => false } }
    client.define_singleton_method(:create_upload) { |**| flunk "no upload should be created" }

    Tempfile.create(["big-file", ".bin"]) do |file|
      source = KnyleShare::UploadSource.prepare(file.path)
      source.define_singleton_method(:byte_size) { 6 * 1024 * 1024 * 1024 }

      KnyleShare::Client.stub :new, client do
        KnyleShare::UploadSource.stub :prepare, source do
          status = cli.run([ file.path, "--public", "--yes" ])

          assert_equal 1, status
        end
      end
    end

    assert_includes stderr.string, "Uploads are limited to 5 GB"
  end
end
