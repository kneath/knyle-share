require "test_helper"
require "json"
require "fileutils"
require "open3"
require "rbconfig"
require "socket"
require "tempfile"
require "tmpdir"
require "uri"

class KnyleShareCliTest < ActiveSupport::TestCase
  class FakeCliApiServer
    attr_reader :uploads

    def initialize(expected_token:, existing_slug: nil)
      @expected_token = expected_token
      @existing_slug = existing_slug
      @uploads = {}
      @next_upload_id = 1
    end

    def start
      @server = TCPServer.new("127.0.0.1", 0)
      @thread = Thread.new { serve_loop }
      self
    end

    def stop
      @stopped = true
      @server&.close
      @thread&.join(1)
    end

    def base_url
      "http://127.0.0.1:#{port}"
    end

    private

    attr_reader :expected_token, :existing_slug

    def port
      @server.addr[1]
    end

    def serve_loop
      until @stopped
        begin
          socket = @server.accept
          handle_connection(socket)
        rescue IOError, Errno::EBADF
          break
        end
      end
    end

    def handle_connection(socket)
      request_line = socket.gets("\r\n")
      return if request_line.nil?

      method, full_path, = request_line.strip.split(" ", 3)
      headers = read_headers(socket)
      body = read_body(socket, headers)
      path, query = full_path.split("?", 2)

      route_request(socket, method:, path:, query:, headers:, body:)
    ensure
      socket.close
    end

    def read_headers(socket)
      headers = {}

      while (line = socket.gets("\r\n"))
        stripped = line.strip
        break if stripped.empty?

        key, value = stripped.split(":", 2)
        headers[key.downcase] = value.to_s.strip
      end

      headers
    end

    def read_body(socket, headers)
      length = headers.fetch("content-length", "0").to_i
      return "" if length.zero?

      socket.read(length)
    end

    def route_request(socket, method:, path:, query:, headers:, body:)
      if path.start_with?("/api/")
        authorization = headers["authorization"]
        unless authorization == "Bearer #{expected_token}"
          return write_json(socket, 401, { error: "Unauthorized" })
        end
      end

      if method == "GET" && path == "/api/v1/bundles/availability"
        params = URI.decode_www_form(query.to_s).to_h
        slug = params["slug"]

        write_json(socket, 200, {
          slug:,
          reserved: false,
          available: slug != existing_slug,
          exists: slug == existing_slug,
          replaceable: slug == existing_slug
        })
      elsif method == "POST" && path == "/api/v1/uploads"
        upload = JSON.parse(body).fetch("upload")
        upload_id = @next_upload_id
        @next_upload_id += 1
        ingest_key = "uploads/#{upload_id}/#{upload.fetch('original_filename')}"
        uploads[upload_id] = {
          params: upload,
          ingest_key:,
          direct_body: nil,
          direct_content_type: nil,
          finalized_byte_size: nil
        }

        write_json(socket, 201, {
          id: upload_id,
          slug: upload.fetch("slug"),
          source_kind: upload.fetch("source_kind"),
          access_mode: upload.fetch("access_mode"),
          replace_existing: upload.fetch("replace_existing"),
          original_filename: upload.fetch("original_filename"),
          ingest_key:,
          status: "pending",
          byte_size: 0,
          upload_url: "#{base_url}/direct-upload/#{upload_id}"
        })
      elsif method == "PUT" && (match = path.match(%r{\A/direct-upload/(\d+)\z}))
        upload_id = match[1].to_i
        uploads.fetch(upload_id)[:direct_body] = body
        uploads.fetch(upload_id)[:direct_content_type] = headers["content-type"]
        write_empty(socket, 200)
      elsif method == "PUT" && (match = path.match(%r{\A/api/v1/uploads/(\d+)\z}))
        upload_id = match[1].to_i
        finalized = JSON.parse(body).fetch("upload")
        uploads.fetch(upload_id)[:finalized_byte_size] = finalized.fetch("byte_size")

        write_json(socket, 200, {
          id: upload_id,
          slug: uploads.fetch(upload_id).dig(:params, "slug"),
          source_kind: uploads.fetch(upload_id).dig(:params, "source_kind"),
          access_mode: uploads.fetch(upload_id).dig(:params, "access_mode"),
          replace_existing: uploads.fetch(upload_id).dig(:params, "replace_existing"),
          original_filename: uploads.fetch(upload_id).dig(:params, "original_filename"),
          ingest_key: uploads.fetch(upload_id).fetch(:ingest_key),
          status: "staged",
          byte_size: finalized.fetch("byte_size")
        })
      elsif method == "POST" && (match = path.match(%r{\A/api/v1/uploads/(\d+)/process\z}))
        upload_id = match[1].to_i
        upload = uploads.fetch(upload_id)
        slug = upload.dig(:params, "slug")

        write_json(socket, 201, {
          id: upload_id,
          slug:,
          source_kind: upload.dig(:params, "source_kind"),
          access_mode: upload.dig(:params, "access_mode"),
          replace_existing: upload.dig(:params, "replace_existing"),
          original_filename: upload.dig(:params, "original_filename"),
          ingest_key: upload.fetch(:ingest_key),
          status: "ready",
          byte_size: upload.fetch(:finalized_byte_size),
          bundle: {
            slug:,
            title: slug.tr("-", " ").split.map(&:capitalize).join(" "),
            presentation_kind: presentation_kind_for(upload),
            content_revision: upload.dig(:params, "replace_existing") ? 2 : 1,
            public_url: "https://share.example.test/#{slug}"
          }
        })
      elsif method == "POST" && (match = path.match(%r{\A/api/v1/bundles/([^/]+)/links\z}))
        slug = match[1]
        params = JSON.parse(body)
        preset = params.fetch("expires_in")

        write_json(socket, 201, {
          slug:,
          expires_in: preset,
          expires_at: "2026-04-19T12:00:00Z",
          url: "https://share.example.test/#{slug}?access=signed-token"
        })
      else
        write_json(socket, 404, { error: "Not found" })
      end
    end

    def presentation_kind_for(upload)
      return "static_site" if upload.dig(:params, "source_kind") == "directory"

      extension = File.extname(upload.dig(:params, "original_filename").to_s).downcase
      %w[.md .markdown].include?(extension) ? "markdown_document" : "single_download"
    end

    def write_json(socket, status, payload)
      body = JSON.generate(payload)
      socket.write <<~HTTP.gsub("\n", "\r\n")
        HTTP/1.1 #{status} #{status_text(status)}
        Content-Type: application/json
        Content-Length: #{body.bytesize}
        Connection: close

        #{body}
      HTTP
    end

    def write_empty(socket, status)
      socket.write <<~HTTP.gsub("\n", "\r\n")
        HTTP/1.1 #{status} #{status_text(status)}
        Content-Length: 0
        Connection: close

      HTTP
    end

    def status_text(status)
      {
        200 => "OK",
        201 => "Created",
        401 => "Unauthorized",
        404 => "Not Found"
      }.fetch(status)
    end
  end

  test "login stores a verified cli configuration" do
    with_fake_server do |server|
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "cli-config.json")
        stdout, stderr, status = run_cli(
          "login",
          "--admin-url", server.base_url,
          "--token", "test-token",
          env: { "KNYLE_SHARE_CONFIG" => config_path }
        )

        assert_predicate status, :success?
        assert_equal "", stderr
        assert_match "Saved CLI configuration", stdout

        config = JSON.parse(File.read(config_path))
        assert_equal server.base_url, config["admin_url"]
        assert_equal "test-token", config["api_token"]
      end
    end
  end

  test "share uploads a protected file and returns json output" do
    with_fake_server do |server|
      Dir.mktmpdir do |dir|
        path = File.join(dir, "Summer in the Sierra.md")
        File.write(path, "# Summer in the Sierra\n")

        stdout, stderr, status = run_cli(
          path,
          "--protected",
          "--generate-password",
          "--link-expiration", "1_week",
          "--json",
          env: {
            "KNYLE_SHARE_ADMIN_URL" => server.base_url,
            "KNYLE_SHARE_API_TOKEN" => "test-token"
          }
        )

        assert_predicate status, :success?
        assert_equal "", stderr

        payload = JSON.parse(stdout)
        assert_equal "summer-in-the-sierra", payload["slug"]
        assert_equal "https://share.example.test/summer-in-the-sierra", payload["share_url"]
        assert_equal "https://share.example.test/summer-in-the-sierra?access=signed-token", payload["signed_url"]
        assert_match(/\A[a-z]+ [a-z]+ [a-z]+\z/, payload["password"])

        upload = server.uploads.fetch(1)
        assert_equal "protected", upload.dig(:params, "access_mode")
        assert_equal false, upload.dig(:params, "replace_existing")
        assert_equal File.binread(path), upload.fetch(:direct_body)
        assert_equal File.size(path), upload.fetch(:finalized_byte_size)
      end
    end
  end

  test "share archives a directory and can replace an existing slug" do
    with_fake_server(existing_slug: "mini-site") do |server|
      Dir.mktmpdir do |dir|
        path = File.join(dir, "mini-site")
        Dir.mkdir(path)
        File.write(File.join(path, "index.html"), "<h1>Mini Site</h1>")
        FileUtils.mkdir_p(File.join(path, "assets"))
        File.write(File.join(path, "assets", "app.css"), "body { color: tomato; }")

        stdout, stderr, status = run_cli(
          path,
          "--slug", "mini-site",
          "--public",
          "--replace",
          "--json",
          env: {
            "KNYLE_SHARE_ADMIN_URL" => server.base_url,
            "KNYLE_SHARE_API_TOKEN" => "test-token"
          }
        )

        assert_predicate status, :success?
        assert_equal "", stderr

        payload = JSON.parse(stdout)
        assert_equal "mini-site", payload["slug"]
        assert_equal "static_site", payload["presentation_kind"]

        upload = server.uploads.fetch(1)
        assert_equal "directory", upload.dig(:params, "source_kind")
        assert_equal true, upload.dig(:params, "replace_existing")
        assert_operator upload.fetch(:direct_body).bytesize, :>, 0
        assert_equal upload.fetch(:direct_body).bytesize, upload.fetch(:finalized_byte_size)
      end
    end
  end

  test "can run through a symlinked executable outside the repo" do
    Dir.mktmpdir("knyle-share-bin") do |dir|
      symlink_path = File.join(dir, "knyle-share")
      File.symlink(Rails.root.join("bin/knyle-share"), symlink_path)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        symlink_path,
        "--help",
        chdir: dir
      )

      assert_predicate status, :success?
      assert_equal "", stderr
      assert_includes stdout, "knyle-share login"
      assert_includes stdout, "knyle-share <path> [options]"
    end
  end

  private

  def with_fake_server(existing_slug: nil)
    server = FakeCliApiServer.new(expected_token: "test-token", existing_slug:).start
    yield server
  ensure
    server&.stop
  end

  def run_cli(*args, env:)
    Open3.capture3(
      env,
      RbConfig.ruby,
      "bin/knyle-share",
      *args,
      chdir: Rails.root.to_s
    )
  end
end
