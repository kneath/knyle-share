require "test_helper"

class PublicBundleDeliveryTest < ActionDispatch::IntegrationTest
  setup do
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all

    host! "share.lvh.me"

    @public_markdown = Bundle.create!(
      slug: "field-notes",
      title: "Field Notes",
      source_kind: "file",
      presentation_kind: "markdown_document",
      access_mode: "public",
      status: "active",
      entry_path: "field-notes.md"
    )
    @public_markdown.assets.create!(
      path: "field-notes.md",
      storage_key: "bundles/#{@public_markdown.id}/1/field-notes.md",
      content_type: "text/markdown",
      byte_size: 512
    )

    @protected_download = Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern",
      entry_path: "private-brief.pdf"
    )
    @protected_download.assets.create!(
      path: "private-brief.pdf",
      storage_key: "bundles/#{@protected_download.id}/1/private-brief.pdf",
      content_type: "application/pdf",
      byte_size: 2048
    )

    @static_site = Bundle.create!(
      slug: "design-review",
      title: "Design Review",
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "public",
      status: "active",
      entry_path: "index.html"
    )
    @static_site.assets.create!(
      path: "index.html",
      storage_key: "bundles/#{@static_site.id}/1/index.html",
      content_type: "text/html",
      byte_size: 1024
    )
    @static_site.assets.create!(
      path: "assets/app.css",
      storage_key: "bundles/#{@static_site.id}/1/assets/app.css",
      content_type: "text/css",
      byte_size: 256
    )

    @disabled_bundle = Bundle.create!(
      slug: "retired-plan",
      title: "Retired Plan",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "public",
      status: "disabled",
      entry_path: "retired-plan.pdf"
    )
    @disabled_bundle.assets.create!(
      path: "retired-plan.pdf",
      storage_key: "bundles/#{@disabled_bundle.id}/1/retired-plan.pdf",
      content_type: "application/pdf",
      byte_size: 128
    )
  end

  test "public markdown bundles render immediately and count document views" do
    with_stubbed_storage(
      "field-notes.md" => "# Heading\n\nHello public bundle.\n\n<script>alert('x')</script>"
    ) do
      get public_bundle_url(slug: @public_markdown.slug, host: "share.lvh.me")
    end

    assert_response :success
    assert_match "Heading", response.body
    assert_no_match "<script>", response.body
    assert_equal 1, @public_markdown.reload.total_views_count
    assert_equal 1, @public_markdown.bundle_views.count
  end

  test "protected bundles require a password and create a viewer session" do
    get public_bundle_url(slug: @protected_download.slug, host: "share.lvh.me")

    assert_response :success
    assert_match "This bundle is protected", response.body

    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      post public_bundle_access_url(slug: @protected_download.slug, host: "share.lvh.me"), params: { password: "river maple lantern" }
      follow_redirect!
    end

    assert_response :success
    assert_match "Download file", response.body
    assert_equal 1, @protected_download.reload.unique_protected_viewers_count
    assert_equal 1, @protected_download.viewer_sessions.count
  end

  test "expired signed links fall back to the password gate" do
    token = BundleAccessLink.generate(bundle: @protected_download, expires_in: 1.minute)

    travel 2.minutes do
      get public_bundle_url(slug: @protected_download.slug, host: "share.lvh.me", access: token)
    end

    assert_response :unauthorized
    assert_match "invalid or has expired", response.body
  end

  test "valid signed links bypass the gate and allow download" do
    token = BundleAccessLink.generate(bundle: @protected_download, expires_in: 1.day)

    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      get public_bundle_url(slug: @protected_download.slug, host: "share.lvh.me", access: token)
      assert_response :success
      assert_match "Download file", response.body
      assert_equal 1, @protected_download.reload.viewer_sessions.count

      get public_download_bundle_url(slug: @protected_download.slug, host: "share.lvh.me")
    end

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal "%PDF-1.7 mock", response.body
  end

  test "static-site html counts as a view but css assets do not" do
    with_stubbed_storage(
      "index.html" => "<h1>Review</h1>",
      "assets/app.css" => "body { color: red; }"
    ) do
      get public_bundle_url(slug: @static_site.slug, host: "share.lvh.me")
      get public_bundle_asset_url(slug: @static_site.slug, asset_path: "assets/app.css", host: "share.lvh.me")
    end

    assert_response :success
    assert_equal 1, @static_site.reload.total_views_count
    assert_equal 1, @static_site.bundle_views.count
  end

  test "disabled bundles render unavailable" do
    get public_bundle_url(slug: @disabled_bundle.slug, host: "share.lvh.me")

    assert_response :gone
    assert_match "Bundle unavailable", response.body
  end

  private

  def with_stubbed_storage(contents)
    fake_storage = Struct.new(:contents) do
      def read(asset)
        raise BundleStorage::MissingObjectError, asset.path unless contents.key?(asset.path)

        contents.fetch(asset.path)
      end

      def fetch(asset)
        {
          body: read(asset),
          content_type: asset.content_type,
          filename: File.basename(asset.path)
        }
      rescue BundleStorage::MissingObjectError
        raise BundleStorage::MissingObjectError, asset.path
      end
    end.new(contents)

    BundleStorage.stub :new, fake_storage do
      yield
    end
  end
end
