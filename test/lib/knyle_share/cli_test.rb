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
end
