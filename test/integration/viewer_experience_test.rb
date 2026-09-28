require "test_helper"

class ViewerExperienceTest < ActionDispatch::IntegrationTest
  setup do
    @bundle = Bundle.create!(slug: "viewer-experience", title: "Private files", source_kind: "directory", presentation_kind: "file_listing", access_mode: "protected", password: "test-password")
    @asset = @bundle.assets.create!(path: "nested/photo.png", storage_key: "viewer/photo.png", content_type: "image/png", byte_size: 20)
    host! "viewer-experience.share.lvh.me"
    @storage = Object.new
    def @storage.download_url(asset, **)
      "https://storage.example.test/#{asset.path}?fresh=1"
    end
    def @storage.public_asset_redirect_ttl_seconds; 300; end
    def @storage.protected_asset_response_cache_control; "private, no-store"; end
    def @storage.public_asset_response_cache_control; "public, max-age=31536000, immutable"; end
  end

  test "unlocking a nested file returns to the original destination" do
    get "/nested/photo.png"
    assert_redirected_to "http://viewer-experience.share.lvh.me/"
    follow_redirect!
    post "/access", params: { password: "test-password" }
    assert_redirected_to "/nested/photo.png"
    BundleStorage.stub :new, @storage do
      follow_redirect!
      assert_redirected_to "https://storage.example.test/nested/photo.png?fresh=1"
    end
  end

  test "media refresh rechecks access and never caches signed urls" do
    get "/_share/media", params: { path: @asset.path }
    assert_response :unauthorized
    post "/access", params: { password: "test-password" }
    BundleStorage.stub :new, @storage do
      get "/_share/media", params: { path: @asset.path }
      assert_response :success
      assert_match "fresh=1", response.parsed_body["url"]
      assert_includes response.headers["Cache-Control"], "no-store"
      @bundle.set_password!("different-password")
      get "/_share/media", params: { path: @asset.path }
      assert_response :unauthorized
    end
  end

  test "protected previews reveal no social description and include accessible image tools" do
    @bundle.update!(description: "Private description")
    post "/access", params: { password: "test-password" }
    BundleStorage.stub :new, @storage do
      get "/_share/preview", params: { path: @asset.path }
      assert_response :success
      assert_select "meta[property='og:description']", 0
      assert_select "button", text: "Actual size"
      assert_select "a", text: "Open original"
    end
  end

  test "canonical and legacy password routes both throttle attempts" do
    previous_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    app = Rack::Attack.new(->(_) { [200, {}, ["ok"]] })
    ["http://viewer-experience.share.lvh.me/access", "http://share.lvh.me/viewer-experience/access"].each do |url|
      Rack::Attack.cache.store.clear
      status = headers = nil
      11.times do
        status, headers, = app.call(Rack::MockRequest.env_for(url, method: "POST", "REMOTE_ADDR" => "192.0.2.17"))
      end
      assert_equal 429, status
      assert_equal "300", headers["Retry-After"]
    end
  ensure
    Rack::Attack.cache.store = previous_store
  end
end
