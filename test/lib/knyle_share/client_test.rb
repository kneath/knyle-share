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
      end
    end
  end
end
