require "test_helper"

class ForwardedHostTest < ActionDispatch::IntegrationTest
  setup do
    BundleAsset.delete_all
    Bundle.delete_all

    @victim = create_static_site!("victim-site")
    @other = create_static_site!("other-site")
    @storage = Object.new
    def @storage.download_url(asset, **) = "https://s3.example/#{asset.storage_key}"
    def @storage.public_asset_redirect_ttl_seconds = 300
    def @storage.public_asset_response_cache_control = "public"
  end

  test "bundle routing ignores a client-supplied X-Forwarded-Host" do
    host! "victim-site.share.lvh.me"

    BundleStorage.stub :new, @storage do
      get "/app.js", headers: { "X-Forwarded-Host" => "other-site.share.lvh.me" }
    end

    assert_response :redirect
    assert_equal "https://s3.example/victim-site/app.js", response.location
  end

  test "admin routing ignores a client-supplied X-Forwarded-Host" do
    host! "victim-site.share.lvh.me"

    get "/login", headers: { "X-Forwarded-Host" => "admin.lvh.me" }

    assert_response :not_found
  end

  private

  def create_static_site!(slug)
    bundle = Bundle.create!(
      slug:,
      title: slug.titleize,
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "public",
      status: "active",
      entry_path: "index.html"
    )
    bundle.assets.create!(path: "app.js", storage_key: "#{slug}/app.js", content_type: "text/javascript", byte_size: 20)
    bundle
  end
end
