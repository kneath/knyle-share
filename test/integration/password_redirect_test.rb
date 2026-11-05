require "test_helper"

class PasswordRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @bundle = Bundle.create!(slug: "password-redirect", title: "Private files", source_kind: "directory", presentation_kind: "file_listing", access_mode: "protected", password: "test-password")
    @bundle.assets.create!(path: "nested/photo.png", storage_key: "viewer/photo.png", content_type: "image/png", byte_size: 20)
    host! "password-redirect.share.lvh.me"
  end

  test "password page icons use the application asset pipeline" do
    get "/"
    assert_response :success
    icons = css_select("link[rel='icon'], link[rel='apple-touch-icon']")
    assert_equal 3, icons.size
    icons.each do |icon|
      assert_match %r{\A/app-assets/icon-[^/]+\.(png|svg)\z}, icon["href"]
      get icon["href"]
      assert_response :success
    end
    unlock
    assert_redirected_to "/"
  end

  test "static site password login ignores background icon requests" do
    @bundle.update!(presentation_kind: "static_site", entry_path: "index.html")
    @bundle.assets.create!(path: "index.html", storage_key: "site/index.html", content_type: "text/html", byte_size: 20)
    get "/"
    assert_response :success
    get "/icon.svg", headers: { "Sec-Fetch-Site" => "same-origin", "Sec-Fetch-Dest" => "image", "Accept" => "image/svg+xml,image/*,*/*;q=0.8" }
    assert_response :redirect
    unlock
    assert_redirected_to "/"

    storage = Object.new
    def storage.read(*)
      "<h1>Private site</h1>"
    end
    BundleStorage.stub :new, storage do
      follow_redirect!
      assert_response :success
      assert_select "h1", "Private site"
    end
  end

  test "background requests do not replace an intentional file destination" do
    get "/nested/photo.png", headers: { "Sec-Fetch-Dest" => "document" }
    follow_redirect!
    [
      ["/nested/photo.png", { "Sec-Fetch-Dest" => "image", "Accept" => "text/html" }],
      ["/style.css", { "Sec-Fetch-Dest" => "style" }],
      ["/script.js", { "Sec-Fetch-Dest" => "script" }],
      ["/other.png", { "Accept" => "image/png,*/*;q=0.8" }],
      ["/data.json", { "Sec-Fetch-Dest" => "empty", "Accept" => "application/json" }],
      ["/xhr", { "X-Requested-With" => "XMLHttpRequest" }],
      ["/icon.svg", {}],
      ["/icon.png", {}],
      ["/favicon.ico", {}]
    ].each do |path, headers|
      get path, headers: headers
      assert_response :redirect
    end
    unlock
    assert_redirected_to "/nested/photo.png"
  end

  test "direct navigation to an uploaded icon is preserved" do
    @bundle.assets.create!(path: "icon.svg", storage_key: "site/icon.svg", content_type: "image/svg+xml", byte_size: 20)
    get "/icon.svg", headers: { "Sec-Fetch-Dest" => "document", "Accept" => "image/svg+xml" }
    follow_redirect!
    unlock
    assert_redirected_to "/icon.svg"
  end

  test "HTML navigation without fetch metadata preserves a file link and query" do
    get "/nested/photo.png?download=1", headers: { "Accept" => "text/html" }
    follow_redirect!
    unlock
    assert_redirected_to "/nested/photo.png?download=1"
  end

  test "folder destinations survive background requests" do
    get "/?prefix=nested&page=2"
    assert_response :success
    get "/other.png", headers: { "Sec-Fetch-Dest" => "image" }
    unlock
    assert_redirected_to "/?prefix=nested&page=2"
  end

  test "missing SVG files render an HTML 404 after unlocking" do
    unlock
    get "/missing.svg", headers: { "Accept" => "image/svg+xml" }
    assert_response :not_found
    assert_equal "text/html", response.media_type
    assert_select "h1", "This file is unavailable"
  end

  test "missing SVG files render an HTML 404 for public bundles" do
    @bundle.update!(access_mode: "public")
    get "/missing.svg", headers: { "Accept" => "image/svg+xml" }
    assert_response :not_found
    assert_equal "text/html", response.media_type
  end

  private

  def unlock
    post "/access", params: { password: "test-password" }
  end
end
