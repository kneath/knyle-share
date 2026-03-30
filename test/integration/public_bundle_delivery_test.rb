require "test_helper"

class PublicBundleDeliveryTest < ActionDispatch::IntegrationTest
  setup do
    BundleUniqueViewer.delete_all
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

    @file_listing_bundle = Bundle.create!(
      slug: "assets-index",
      title: "Assets Index",
      source_kind: "directory",
      presentation_kind: "file_listing",
      access_mode: "public",
      status: "active",
      entry_path: "index.html"
    )
    75.times do |index|
      path = format("assets/file-%03d.txt", index + 1)
      @file_listing_bundle.assets.create!(
        path:,
        storage_key: "bundles/#{@file_listing_bundle.id}/1/#{path}",
        content_type: "text/plain",
        byte_size: index + 1
      )
    end
    @file_listing_bundle.assets.create!(
      path: "README.txt",
      storage_key: "bundles/#{@file_listing_bundle.id}/1/README.txt",
      content_type: "text/plain",
      byte_size: 256
    )
    @file_listing_bundle.assets.create!(
      path: "Additional Candidates - Research.md",
      storage_key: "bundles/#{@file_listing_bundle.id}/1/Additional Candidates - Research.md",
      content_type: "text/markdown",
      byte_size: 512
    )

    @protected_static_site = Bundle.create!(
      slug: "private-review",
      title: "Private Review",
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern",
      entry_path: "index.html"
    )
    @protected_static_site.assets.create!(
      path: "index.html",
      storage_key: "bundles/#{@protected_static_site.id}/1/index.html",
      content_type: "text/html",
      byte_size: 512
    )
    @protected_static_site.assets.create!(
      path: "assets/app.js",
      storage_key: "bundles/#{@protected_static_site.id}/1/assets/app.js",
      content_type: "application/javascript",
      byte_size: 128
    )

    @public_image = Bundle.create!(
      slug: "sunset-photo",
      title: "Sunset Photo",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "public",
      status: "active",
      entry_path: "sunset.jpg"
    )
    @public_image.assets.create!(
      path: "sunset.jpg",
      storage_key: "bundles/#{@public_image.id}/1/sunset.jpg",
      content_type: "image/jpeg",
      byte_size: 1_500_000
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
    get public_bundle_url(slug: @public_markdown.slug, host: "share.lvh.me")

    assert_redirected_to "http://field-notes.share.lvh.me/"

    with_stubbed_storage(
      "field-notes.md" => "# Heading\n\nHello public bundle.\n\n<script>alert('x')</script>"
    ) do
      perform_enqueued_jobs do
        get "http://field-notes.share.lvh.me/"
      end
    end

    assert_response :success
    assert_match "Heading", response.body
    assert_no_match "<script>", response.body
    assert_includes response.headers.fetch("Server-Timing"), "bundle-storage-read"
    assert_includes response.headers.fetch("Server-Timing"), "bundle-markdown-render"
    assert_includes response.headers.fetch("Server-Timing"), "bundle-analytics-enqueue"
    assert_equal 1, @public_markdown.reload.total_views_count
    assert_equal 1, @public_markdown.bundle_views.count
  end

  test "public markdown responses are cacheable and return 304 on a matching etag" do
    with_stubbed_storage(
      "field-notes.md" => "# Heading\n\nHello public bundle."
    ) do |fake_storage|
      perform_enqueued_jobs do
        get "http://field-notes.share.lvh.me/"
      end

      assert_response :success
      assert_match "Heading", response.body
      assert_includes response.headers.fetch("Cache-Control"), "public"
      assert_includes response.headers.fetch("Cache-Control"), "max-age=300"
      assert_includes response.headers.fetch("Cache-Control"), "s-maxage=300"
      assert_includes response.headers.fetch("Cache-Control"), "stale-while-revalidate=60"

      etag = response.headers.fetch("ETag")
      assert_equal [ "field-notes.md" ], fake_storage.reads

      get "http://field-notes.share.lvh.me/", headers: { "If-None-Match" => etag }

      assert_response :not_modified
      assert_equal [ "field-notes.md" ], fake_storage.reads
      assert_equal 1, @public_markdown.reload.total_views_count
    end
  end

  test "public markdown bundles render when the storage body is ascii-8bit" do
    binary_markdown = "# Heading\n\nHello binary markdown.\n".b

    with_stubbed_storage(
      "field-notes.md" => binary_markdown
    ) do
      perform_enqueued_jobs do
        get "http://field-notes.share.lvh.me/"
      end
    end

    assert_response :success
    assert_match "Heading", response.body
    assert_match "Hello binary markdown.", response.body
  end

  test "public markdown pages use prerendered html when it is available" do
    @public_markdown.assets.first.update!(
      rendered_html: "<h1>Pre-rendered</h1>\n<p>Fast path.</p>",
      rendered_html_version: BundleMarkdownRenderer::VERSION
    )

    with_stubbed_storage({}) do |fake_storage|
      perform_enqueued_jobs do
        get "http://field-notes.share.lvh.me/"
      end

      assert_response :success
      assert_match "Pre-rendered", response.body
      assert_match "Fast path.", response.body
      assert_includes response.headers.fetch("Server-Timing"), "bundle-analytics-enqueue"
      assert_not_includes response.headers.fetch("Server-Timing"), "bundle-storage-read"
      assert_not_includes response.headers.fetch("Server-Timing"), "bundle-markdown-render"
      assert_empty fake_storage.reads
    end
  end

  test "protected bundles require a password and create a viewer session" do
    get public_bundle_url(slug: @protected_download.slug, host: "share.lvh.me")

    assert_redirected_to "http://private-brief.share.lvh.me/"

    get "http://private-brief.share.lvh.me/"

    assert_response :success
    assert_match "This bundle is protected", response.body

    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      perform_enqueued_jobs do
        post "http://private-brief.share.lvh.me/access", params: { password: "river maple lantern" }
        follow_redirect!
      end
    end

    assert_response :success
    assert_match "Download file", response.body
    assert_equal 1, @protected_download.reload.unique_protected_viewers_count
    assert_equal 1, @protected_download.viewer_sessions.count
  end

  test "expired signed links fall back to the password gate" do
    token = BundleAccessLink.generate(bundle: @protected_download, expires_in: 1.minute)

    travel 2.minutes do
      get "http://private-brief.share.lvh.me/", params: { access: token }
    end

    assert_response :unauthorized
    assert_match "invalid or has expired", response.body
  end

  test "valid signed links bypass the gate and allow download" do
    token = BundleAccessLink.generate(bundle: @protected_download, expires_in: 1.day)

    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      perform_enqueued_jobs do
        get "http://private-brief.share.lvh.me/", params: { access: token }
      end
      assert_response :success
      assert_match "Download file", response.body
      assert_equal 1, @protected_download.reload.viewer_sessions.count

      get "http://private-brief.share.lvh.me/download"
    end

    assert_redirected_to "https://downloads.example.test/private-brief.pdf?disposition=attachment"
  end

  test "password rotation invalidates existing viewer sessions and signed links" do
    token = BundleAccessLink.generate(bundle: @protected_download, expires_in: 1.day)

    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      post "http://private-brief.share.lvh.me/access", params: { password: "river maple lantern" }
      assert_redirected_to "http://private-brief.share.lvh.me/"

      @protected_download.reload.set_password!("sunlit amber harbor")

      get "http://private-brief.share.lvh.me/download"
      assert_redirected_to "http://private-brief.share.lvh.me/"

      follow_redirect!
      assert_response :success
      assert_match "This bundle is protected", response.body

      get "http://private-brief.share.lvh.me/", params: { access: token }
    end

    assert_response :unauthorized
    assert_match "invalid or has expired", response.body
  end

  test "image bundles render an inline image display instead of the download card" do
    with_stubbed_storage("sunset.jpg" => "fake jpeg bytes") do |fake_storage|
      perform_enqueued_jobs do
        get "http://sunset-photo.share.lvh.me/"
      end

      assert_response :success
      assert_match "image-display", response.body
      assert_match "sunset-photo.share.lvh.me/download", response.body
      assert_equal 1, fake_storage.downloads.size
      assert_equal "inline", fake_storage.downloads.first[:disposition]
      assert_equal 1, @public_image.reload.total_views_count
    end
  end

  test "non-image single downloads still render the download card" do
    with_stubbed_storage("private-brief.pdf" => "%PDF-1.7 mock") do
      perform_enqueued_jobs do
        post "http://private-brief.share.lvh.me/access", params: { password: "river maple lantern" }
        follow_redirect!
      end

      assert_response :success
      assert_no_match "image-display", response.body
      assert_match "Download file", response.body
    end
  end

  test "static-site bundle paths on the shared host redirect to the isolated bundle host" do
    get public_bundle_url(slug: @static_site.slug, host: "share.lvh.me")

    assert_redirected_to "http://design-review.share.lvh.me/"
  end

  test "static-site html counts as a view but css assets do not on the isolated host" do
    with_stubbed_storage(
      "index.html" => "<h1>Review</h1>",
      "assets/app.css" => "body { color: red; }"
    ) do
      perform_enqueued_jobs do
        get "http://design-review.share.lvh.me/"
      end
      get "http://design-review.share.lvh.me/assets/app.css"
    end

    assert_redirected_to "https://downloads.example.test/assets/app.css?disposition=inline"
    assert_equal 1, @static_site.reload.total_views_count
    assert_equal 1, @static_site.bundle_views.count
  end

  test "file listings render directory-aware navigation with paginated children" do
    perform_enqueued_jobs do
      get "http://assets-index.share.lvh.me/"
    end

    assert_response :success
    assert_select ".bundle-item", 3
    assert_match "All files", response.body
    assert_match "assets/", response.body
    assert_match "README.txt", response.body
    assert_match "Additional Candidates - Research.md", response.body
    assert_match "/Additional%20Candidates%20-%20Research.md", response.body
    assert_no_match "file-001.txt", response.body

    perform_enqueued_jobs do
      get "http://assets-index.share.lvh.me/", params: { prefix: "assets" }
    end

    assert_response :success
    assert_select ".bundle-item", 50
    assert_match "assets", response.body
    assert_match "Page 1 of 2", response.body
    assert_no_match "file-051.txt", response.body
    assert_match "file-001.txt", response.body
    assert_match "file-050.txt", response.body
    assert_match "Next", response.body

    perform_enqueued_jobs do
      get "http://assets-index.share.lvh.me/", params: { prefix: "assets/", page: 2 }
    end

    assert_response :success
    assert_select ".bundle-item", 25
    assert_match "Page 2 of 2", response.body
    assert_match "file-051.txt", response.body
    assert_match "file-075.txt", response.body
    assert_no_match "file-050.txt", response.body
    assert_match "Previous", response.body
  end

  test "file listings reject invalid or missing directory prefixes" do
    get "http://assets-index.share.lvh.me/", params: { prefix: "../private" }

    assert_response :not_found
    assert_match "Directory not found", response.body

    get "http://assets-index.share.lvh.me/", params: { prefix: "missing" }

    assert_response :not_found
    assert_match "Directory not found", response.body
  end

  test "public asset redirects are cacheable and protected asset redirects are not" do
    with_stubbed_storage(
      "index.html" => "<h1>Review</h1>",
      "assets/app.css" => "body { color: red; }",
      "assets/app.js" => "console.log('private review');"
    ) do |fake_storage|
      get "http://design-review.share.lvh.me/assets/app.css"

      assert_redirected_to "https://downloads.example.test/assets/app.css?disposition=inline"
      assert_includes response.headers.fetch("Cache-Control"), "public"
      assert_includes response.headers.fetch("Cache-Control"), "max-age=300"
      assert_equal "public, max-age=31536000, immutable", fake_storage.downloads.last.fetch(:response_cache_control)

      post "http://private-review.share.lvh.me/access", params: { password: "river maple lantern" }

      get "http://private-review.share.lvh.me/assets/app.js", headers: { "Sec-Fetch-Site" => "same-origin" }

      assert_redirected_to "https://downloads.example.test/assets/app.js?disposition=inline"
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "no-cache", response.headers["Pragma"]
      assert_equal "private, no-store", fake_storage.downloads.last.fetch(:response_cache_control)
    end
  end

  test "protected static sites establish an isolated-host viewer session that covers nested assets" do
    with_stubbed_storage(
      "index.html" => "<h1>Private Review</h1>",
      "assets/app.js" => "console.log('private review');"
    ) do
      get "http://private-review.share.lvh.me/"

      assert_response :success
      assert_match "This bundle is protected", response.body

      perform_enqueued_jobs do
        post "http://private-review.share.lvh.me/access", params: { password: "river maple lantern" }
        assert_redirected_to "http://private-review.share.lvh.me/"

        follow_redirect!
      end
      assert_response :success
      assert_match "Private Review", response.body

      get "http://private-review.share.lvh.me/assets/app.js", headers: { "Sec-Fetch-Site" => "same-origin" }
    end

    assert_redirected_to "https://downloads.example.test/assets/app.js?disposition=inline"
    assert_equal 1, @protected_static_site.reload.viewer_sessions.count
  end

  test "large markdown bundles fall back to a download-oriented page" do
    @public_markdown.assets.first.update!(byte_size: 2.megabytes)

    with_stubbed_storage(
      "field-notes.md" => "# Heading\n\nHello public bundle."
    ) do
      get "http://field-notes.share.lvh.me/"
    end

    assert_response :success
    assert_match "too large to render inline", response.body
    assert_match "View raw markdown", response.body
  end

  test "protected static assets reject same-site cross-subdomain requests" do
    with_stubbed_storage(
      "index.html" => "<h1>Private Review</h1>",
      "assets/app.js" => "console.log('private review');"
    ) do
      post "http://private-review.share.lvh.me/access", params: { password: "river maple lantern" }

      get "http://private-review.share.lvh.me/assets/app.js", headers: { "Sec-Fetch-Site" => "same-site" }
    end

    assert_response :not_found
  end

  test "disabled bundles render unavailable" do
    get public_bundle_url(slug: @disabled_bundle.slug, host: "share.lvh.me")

    assert_redirected_to "http://retired-plan.share.lvh.me/"

    get "http://retired-plan.share.lvh.me/"

    assert_response :gone
    assert_match "Bundle unavailable", response.body
  end

  test "protected pages revalidate privately and never return 304 after access is revoked" do
    with_stubbed_storage(
      "private-brief.pdf" => "%PDF-1.7 mock"
    ) do
      perform_enqueued_jobs do
        post "http://private-brief.share.lvh.me/access", params: { password: "river maple lantern" }
        follow_redirect!
      end

      assert_response :success
      perform_enqueued_jobs do
        get "http://private-brief.share.lvh.me/"
      end

      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "private"
      assert_includes response.headers.fetch("Cache-Control"), "no-cache"

      etag = response.headers.fetch("ETag")

      get "http://private-brief.share.lvh.me/", headers: { "If-None-Match" => etag }

      assert_response :not_modified

      @protected_download.reload.set_password!("sunlit amber harbor")

      get "http://private-brief.share.lvh.me/", headers: { "If-None-Match" => etag }

      assert_response :success
      assert_match "This bundle is protected", response.body
    end
  end

  private

  def with_stubbed_storage(contents)
    fake_storage = Struct.new(:contents, :reads, :downloads) do
      def read(asset)
        reads << asset.path
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

      def download_url(asset, disposition:, expires_in: 5.minutes, response_cache_control: nil)
        downloads << {
          path: asset.path,
          disposition:,
          expires_in: expires_in.to_i,
          response_cache_control:
        }
        "https://downloads.example.test/#{asset.path}?disposition=#{disposition}"
      end

      def render_markdown_inline?(asset)
        asset.byte_size <= 1.megabyte
      end

      def public_asset_redirect_ttl_seconds
        5.minutes.to_i
      end

      def public_asset_response_cache_control
        "public, max-age=31536000, immutable"
      end

      def protected_asset_response_cache_control
        "private, no-store"
      end
    end.new(contents, [], [])

    BundleStorage.stub :new, fake_storage do
      yield fake_storage
    end
  end
end
