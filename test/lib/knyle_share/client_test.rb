require "test_helper"
require "tempfile"
require_relative "../../../lib/knyle_share/client"

class KnyleShareClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:body, :code, :message) do
    def is_a?(klass)
      return false if klass == Net::HTTPSuccess

      super
    end
  end

  test "raises a clean api error when the server returns html instead of json" do
    client = KnyleShare::Client.new(admin_url: "http://admin.example.test", api_token: "secret")
    response = FakeResponse.new("<!DOCTYPE html><html></html>", "500", "Internal Server Error")

    error = assert_raises(KnyleShare::ApiError) do
      client.send(:parse_json_response, response)
    end

    assert_equal 500, error.status
    assert_match "non-JSON response", error.message
  end

  test "rejects admin urls without an http scheme and host" do
    [
      "ftp://admin.example.test",
      "https:///missing-host",
      "not a url"
    ].each do |admin_url|
      error = assert_raises(KnyleShare::Error) do
        KnyleShare::Client.new(admin_url:, api_token: "secret")
      end

      assert_equal "Admin URL must be an http or https URL with a host.", error.message
    end
  end

  test "wraps expected network failures with the host and failure kind" do
    failures = [
      [ Errno::ECONNREFUSED.new, "refused" ],
      [ Errno::ECONNRESET.new, "reset" ],
      [ Errno::EHOSTUNREACH.new, "unreachable" ],
      [ SocketError.new("getaddrinfo failed"), "resolve" ],
      [ Net::OpenTimeout.new("open timed out"), "timed out" ],
      [ Net::ReadTimeout.new("read timed out"), "reading" ],
      [ OpenSSL::SSL::SSLError.new("certificate verify failed"), "TLS negotiation" ]
    ]

    failures.each do |exception, failure_kind|
      client = KnyleShare::Client.new(admin_url: "https://admin.example.test", api_token: "secret")

      Net::HTTP.stub :start, ->(*, **, &_) { raise exception } do
        error = assert_raises(KnyleShare::Error) do
          client.availability(slug: "example")
        end

        assert_includes error.message, "admin.example.test"
        assert_includes error.message, failure_kind
      end
    end
  end

  test "wraps tls failures during direct upload in a cli-friendly error" do
    Tempfile.create("knyle-share-upload") do |file|
      file.write("hello")
      file.flush

      client = KnyleShare::Client.new(admin_url: "http://admin.example.test", api_token: "secret")

      Net::HTTP.stub :start, ->(*, **, &_) { raise OpenSSL::SSL::SSLError, "certificate verify failed" } do
        error = assert_raises(KnyleShare::Error) do
          client.put_file(
            upload_url: "https://s3.example.test/upload",
            file_path: file.path,
            content_type: "text/plain"
          )
        end

        assert_match "TLS negotiation", error.message
        assert_match "s3.example.test", error.message
      end
    end
  end
end
