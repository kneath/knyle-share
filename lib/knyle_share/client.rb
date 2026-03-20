require "json"
require "net/http"
require "openssl"
require "uri"
require_relative "../../app/services/aws_client_options"

module KnyleShare
  class Error < StandardError; end

  class ApiError < Error
    attr_reader :status, :payload

    def initialize(message, status:, payload: nil)
      super(message)
      @status = status
      @payload = payload
    end
  end

  class Client
    def initialize(admin_url:, api_token:)
      @admin_url = normalize_admin_url(admin_url)
      @api_token = api_token.to_s
    end

    def availability(slug:)
      request_json(:get, "/api/v1/bundles/availability", params: { slug: })
    end

    def create_upload(slug:, source_kind:, original_filename:, access_mode:, replace_existing:, password: nil)
      request_json(
        :post,
        "/api/v1/uploads",
        body: {
          upload: {
            slug:,
            source_kind:,
            original_filename:,
            access_mode:,
            replace_existing:,
            password:
          }.compact
        }
      )
    end

    def finalize_upload(id:, byte_size:)
      request_json(
        :put,
        "/api/v1/uploads/#{id}",
        body: {
          upload: {
            byte_size:
          }
        }
      )
    end

    def process_upload(id:)
      request_json(:post, "/api/v1/uploads/#{id}/process")
    end

    def bundle(slug:)
      request_json(:get, "/api/v1/bundles/#{slug}")
    end

    def create_link(slug:, expires_in:)
      request_json(
        :post,
        "/api/v1/bundles/#{slug}/links",
        body: {
          expires_in:
        }
      )
    end

    def put_file(upload_url:, file_path:, content_type:)
      uri = URI(upload_url)

      File.open(file_path, "rb") do |file|
        request = Net::HTTP::Put.new(uri)
        request["Content-Type"] = content_type
        request.body_stream = file
        request.content_length = file.size

        response = start_http(uri) do |http|
          http.request(request)
        end

        return if response.is_a?(Net::HTTPSuccess)

        raise ApiError.new(
          "Upload failed with #{response.code} #{response.message}.",
          status: response.code.to_i
        )
      end
    rescue OpenSSL::SSL::SSLError => error
      raise Error, "Direct upload failed during TLS negotiation: #{error.message}"
    end

    private

    attr_reader :admin_url, :api_token

    def request_json(method, path, params: nil, body: nil)
      uri = build_uri(path, params:)
      request = request_class_for(method).new(uri)
      request["Authorization"] = "Bearer #{api_token}"

      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      response = start_http(uri) do |http|
        http.request(request)
      end

      parse_json_response(response)
    end

    def build_uri(path, params: nil)
      uri = URI(admin_url)
      base_path = uri.path.to_s.sub(%r{/+\z}, "")
      api_path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
      combined_path = [ base_path, api_path ].join
      uri.path = combined_path.start_with?("/") ? combined_path : "/#{combined_path}"
      uri.query = params ? URI.encode_www_form(params) : nil
      uri
    end

    def start_http(uri, &block)
      options = { use_ssl: uri.scheme == "https" }
      options[:cert_store] = AwsClientOptions.ssl_ca_store if uri.scheme == "https" && AwsClientOptions.ssl_ca_store

      Net::HTTP.start(uri.host, uri.port, **options, &block)
    end

    def parse_json_response(response)
      payload = parse_json_body(response)

      return payload if response.is_a?(Net::HTTPSuccess)

      message = payload["error"] || "#{response.code} #{response.message}"
      raise ApiError.new(message, status: response.code.to_i, payload:)
    end

    def parse_json_body(response)
      body = response.body.to_s
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      message = "API returned #{response.code} #{response.message} with a non-JSON response."
      raise ApiError.new(message, status: response.code.to_i, payload: { "raw_body" => body })
    end

    def request_class_for(method)
      case method.to_sym
      when :get then Net::HTTP::Get
      when :post then Net::HTTP::Post
      when :put then Net::HTTP::Put
      when :patch then Net::HTTP::Patch
      when :delete then Net::HTTP::Delete
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end
    end

    def normalize_admin_url(value)
      url = value.to_s.strip
      raise Error, "Admin URL is required." if url.empty?

      url.sub(%r{/+\z}, "")
    end
  end
end
