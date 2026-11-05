require "test_helper"

class BundleSlugSourceTest < ActionDispatch::IntegrationTest
  setup do
    BundleAsset.delete_all
    Bundle.delete_all

    @private_listing = Bundle.create!(slug: "private-listing", title: "Private", source_kind: "directory", presentation_kind: "file_listing", access_mode: "protected", password: "river maple lantern", status: "active")
    @private_listing.assets.create!(path: "notes.md", storage_key: "private/notes.md", content_type: "text/markdown", byte_size: 20)
    @public_listing = Bundle.create!(slug: "public-listing", title: "Public", source_kind: "directory", presentation_kind: "file_listing", access_mode: "public", status: "active")
    @public_listing.assets.create!(path: "readme.md", storage_key: "public/readme.md", content_type: "text/markdown", byte_size: 20)
    @storage = Object.new
    def @storage.download_url(asset, **) = "https://s3.example/#{asset.storage_key}"
    def @storage.render_markdown_inline?(_) = true
    def @storage.read(asset) = "# Content of #{asset.storage_key}"
  end

  test "a slug query param can't swap in another bundle on a bundle subdomain" do
    host! "private-listing.share.lvh.me"

    BundleStorage.stub :new, @storage do
      get "/_share/preview", params: { slug: "public-listing", path: "readme.md" }
      assert_redirected_to "http://private-listing.share.lvh.me/"

      get "/_share/original", params: { slug: "public-listing", path: "readme.md" }
      assert_not_equal "https://s3.example/public/readme.md", response.location
    end
  end

  test "a slug query param can't name a bundle on a host that has none" do
    host! "no-such-bundle.share.lvh.me"

    BundleStorage.stub :new, @storage do
      get "/_share/preview", params: { slug: "public-listing", path: "readme.md" }
    end

    assert_response :not_found
  end

  test "the subdomain still picks the bundle for share routes" do
    host! "public-listing.share.lvh.me"

    BundleStorage.stub :new, @storage do
      get "/_share/preview", params: { path: "readme.md" }
    end

    assert_response :success
    assert_includes response.body, "Content of public/readme.md"
  end
end
