require "test_helper"

class BundleRenderCacheTest < ActionDispatch::IntegrationTest
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all

    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @listing = Bundle.create!(slug: "notes-listing", title: "Notes", source_kind: "directory", presentation_kind: "file_listing", access_mode: "public", status: "active")
    @listing.assets.create!(path: "readme.md", storage_key: "listing/readme.md", content_type: "text/markdown", byte_size: 20, checksum: "abc")
    @document = Bundle.create!(slug: "field-notes", title: "Field Notes", source_kind: "file", presentation_kind: "markdown_document", access_mode: "public", status: "active", entry_path: "field-notes.md")
    @document_asset = @document.assets.create!(path: "field-notes.md", storage_key: "document/field-notes.md", content_type: "text/markdown", byte_size: 20,
      rendered_html: "<p>stale</p>", rendered_html_version: "old-version")

    @reads = reads = []
    @storage = Object.new
    @storage.define_singleton_method(:read) { |asset| reads << asset.storage_key; "# Heading for #{asset.storage_key}" }
    @storage.define_singleton_method(:render_markdown_inline?) { |_| true }
    @storage.define_singleton_method(:download_url) { |asset, **| "https://s3.example/#{asset.storage_key}" }
  end

  teardown do
    Rails.cache = @previous_cache
  end

  test "small static-site pages are read from storage once" do
    site = Bundle.create!(slug: "private-site", title: "Private Site", source_kind: "directory", presentation_kind: "static_site", access_mode: "protected",
      password: "river maple lantern", status: "active", entry_path: "index.html")
    site.assets.create!(path: "index.html", storage_key: "site/index.html", content_type: "text/html", byte_size: 30, checksum: "abc")
    site.assets.create!(path: "huge.html", storage_key: "site/huge.html", content_type: "text/html", byte_size: 2.megabytes, checksum: "def")
    host! "private-site.share.lvh.me"

    BundleStorage.stub :new, @storage do
      post "/access", params: { password: "river maple lantern" }
      2.times do
        get "/", headers: { "If-None-Match" => "different" }
        assert_response :success
        assert_includes response.body, "Heading for site/index.html"
        assert_match(/private/, response.headers["Cache-Control"])
      end
      2.times { get "/huge.html", headers: { "Sec-Fetch-Site" => "same-origin" } }
    end

    assert_equal ["site/index.html", "site/huge.html", "site/huge.html"], @reads
  end

  test "file listing previews render a markdown file once" do
    host! "notes-listing.share.lvh.me"

    BundleStorage.stub :new, @storage do
      2.times do
        get "/_share/preview", params: { path: "readme.md" }
        assert_response :success
        assert_includes response.body, "Heading for listing/readme.md"
      end
    end

    assert_equal ["listing/readme.md"], @reads
  end

  test "a document rendered by an older renderer is re-rendered once and saved" do
    host! "field-notes.share.lvh.me"

    BundleStorage.stub :new, @storage do
      get "/"
      assert_response :success
      assert_includes response.body, "Heading for document/field-notes.md"

      Rails.cache.clear
      get "/", headers: { "If-None-Match" => "different" }
      assert_response :success
    end

    assert_equal ["document/field-notes.md"], @reads
    @document_asset.reload
    assert_equal BundleMarkdownRenderer::VERSION, @document_asset.rendered_html_version
    assert_includes @document_asset.rendered_html, "Heading for document/field-notes.md"
  end
end
