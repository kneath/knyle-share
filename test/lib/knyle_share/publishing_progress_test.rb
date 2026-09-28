require "test_helper"
require "tempfile"
require_relative "../../../lib/knyle_share"

class PublishingProgressTest < ActiveSupport::TestCase
  test "upload stream reports actual transferred bytes" do
    Tempfile.create("progress") do |file|
      file.write("abcdefghij"); file.rewind
      progress = []
      stream = KnyleShare::Client::ProgressStream.new(file) { |sent, total| progress << [sent, total] }
      destination = StringIO.new
      IO.copy_stream(stream, destination)
      assert_equal "abcdefghij", destination.string
      assert_equal [10, 10], progress.last
    end
  end

  test "link failure reports successful publication in json" do
    client = Object.new
    def client.availability(**); { "available" => true }; end
    def client.create_upload(**); { "id" => 9, "upload_url" => "http://example.test/upload" }; end
    def client.put_file(**); end
    def client.finalize_upload(**); end
    def client.process_upload(**); { "bundle" => { "slug" => "notes", "public_url" => "http://notes.example.test/", "presentation_kind" => "single_download", "content_revision" => 1 } }; end
    def client.create_link(**); raise KnyleShare::Error, "Unavailable"; end
    output = StringIO.new
    config = Struct.new(:load).new({ admin_url: "http://admin.example.test", api_token: "token" })
    cli = KnyleShare::Cli.new(stdin: StringIO.new, stdout: output, stderr: StringIO.new, config_store: config)
    Tempfile.create(["notes", ".txt"]) do |file|
      file.write("hello"); file.flush
      KnyleShare::Client.stub :new, client do
        assert_equal 0, cli.run([file.path, "--protected", "--generate-password", "--link-expiration", "1_day", "--json"])
      end
    end
    result = JSON.parse(output.string)
    assert_equal "http://notes.example.test/", result["share_url"]
    assert_includes result["warning"], "published successfully"
    assert_match(/\A[A-Za-z0-9_-]{22}\z/, result["password"])
  end

  test "resume publishes a staged upload without transferring files" do
    client = Object.new
    def client.process_upload(id:)
      raise "wrong id" unless id == "9"
      { "bundle" => { "slug" => "notes", "public_url" => "http://notes.example.test/" } }
    end
    config = Struct.new(:load).new({ admin_url: "http://admin.example.test", api_token: "token" })
    output = StringIO.new
    cli = KnyleShare::Cli.new(stdin: StringIO.new, stdout: output, stderr: StringIO.new, config_store: config)
    KnyleShare::Client.stub :new, client do
      assert_equal 0, cli.run(["resume", "9", "--json"])
    end
    assert_equal "http://notes.example.test/", JSON.parse(output.string)["share_url"]
  end
end
