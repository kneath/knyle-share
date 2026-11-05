require "test_helper"
require "stringio"
require "tmpdir"
require_relative "../../lib/knyle_share"

class ScopedCliLoginTest < ActionDispatch::IntegrationTest
  setup do
    host! "admin.lvh.me"
  end

  test "login saves scoped and unrestricted tokens without checking bundle availability" do
    ["kb-", nil].each do |prefix|
      token, plaintext = ApiToken.issue!(label: "CLI", slug_prefix: prefix)

      with_cli_login(plaintext) do |status, config_path, stderr|
        assert_equal 0, status, stderr
        assert_equal plaintext, JSON.parse(File.read(config_path)).fetch("api_token")
        assert_equal "/api/v1/token", request.path
        assert_equal({ "slug_prefix" => prefix }, response.parsed_body)
        assert_not_nil token.reload.last_used_at
      end
    end
  end

  test "login rejects invalid and revoked tokens without saving them" do
    token, plaintext = ApiToken.issue!(label: "CLI", slug_prefix: "kb-")
    token.revoke!

    ["invalid-token", plaintext].each do |credential|
      with_cli_login(credential) do |status, config_path, stderr|
        assert_equal 1, status
        assert_includes stderr, "Unauthorized"
        assert_not File.exist?(config_path)
        assert_response :unauthorized
        assert_equal "/api/v1/token", request.path
      end
    end
  end

  private

  def with_cli_login(plaintext)
    # Send the real client's HTTP requests through Rails' integration session.
    transport = Object.new
    dispatch = lambda do |http_request|
      get http_request.path, headers: { "Authorization" => http_request["Authorization"] }
      http_response = Net::HTTPResponse::CODE_TO_OBJ.fetch(response.status.to_s).new("1.1", response.status.to_s, "")
      body = response.body
      http_response.define_singleton_method(:body) { body }
      http_response
    end
    transport.define_singleton_method(:request) { |http_request| dispatch.call(http_request) }

    Dir.mktmpdir("knyle-share-login") do |dir|
      config_path = File.join(dir, "config.json")
      stderr = StringIO.new
      cli = KnyleShare::Cli.new(
        stdout: StringIO.new,
        stderr:,
        config_store: KnyleShare::ConfigStore.new(env: { "KNYLE_SHARE_CONFIG" => config_path })
      )

      Net::HTTP.stub :start, ->(*, **, &block) { block.call(transport) } do
        status = cli.run(["login", "--admin-url", "http://admin.lvh.me", "--token", plaintext])
        yield status, config_path, stderr.string
      end
    end
  end
end
