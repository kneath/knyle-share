require "test_helper"
require "fileutils"
require "rack/mock"
require "tmpdir"

class BundleSubdomainStaticTest < ActiveSupport::TestCase
  setup do
    @original_public_host = ENV["PUBLIC_HOST"]
    ENV["PUBLIC_HOST"] = "share.example.test"
  end

  teardown do
    ENV["PUBLIC_HOST"] = @original_public_host
  end

  test "serves app assets on bundle subdomains" do
    Dir.mktmpdir("knyle-share-static") do |dir|
      FileUtils.mkdir_p(File.join(dir, "app-assets"))
      File.write(File.join(dir, "app-assets", "application.css"), "body { color: tomato; }\n")

      middleware = BundleSubdomainStatic.new(fallback_app, dir)
      env = Rack::MockRequest.env_for("http://design-review.share.example.test/app-assets/application.css")

      status, headers, body = middleware.call(env)

      assert_equal 200, status
      assert_match "text/css", headers.fetch("content-type")
      assert_equal "body { color: tomato; }\n", read_body(body)
    end
  end

  test "still defers non-app-asset paths to bundle routing on bundle subdomains" do
    Dir.mktmpdir("knyle-share-static") do |dir|
      File.write(File.join(dir, "styles.css"), "body { color: tomato; }\n")

      middleware = BundleSubdomainStatic.new(fallback_app, dir)
      env = Rack::MockRequest.env_for("http://design-review.share.example.test/styles.css")

      status, headers, body = middleware.call(env)

      assert_equal 418, status
      assert_equal "text/plain", headers.fetch("content-type")
      assert_equal "fallback", read_body(body)
    end
  end

  private

  def read_body(body)
    output = +""
    body.each { |chunk| output << chunk }
    output
  ensure
    body.close if body.respond_to?(:close)
  end

  def fallback_app
    lambda do |_env|
      [418, { "content-type" => "text/plain" }, ["fallback"]]
    end
  end
end
