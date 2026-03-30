require "test_helper"

class AdminUploadTest < ActionDispatch::IntegrationTest
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all
    BundleUpload.delete_all
    Installation.delete_all

    host! "admin.lvh.me"

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "12345", login: "kneath")

    Installation.create!(
      admin_github_uid: "12345",
      admin_github_login: "kneath",
      admin_github_name: "Kyle Neath",
      admin_claimed_at: Time.current
    )

    get "/auth/github/callback"
    follow_redirect!
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "bundles index links to new bundle page" do
    get admin_bundles_url(host: "admin.lvh.me")

    assert_response :success
    assert_match "New bundle", response.body
    assert_match "/bundles/new", response.body
  end

  test "new bundle page renders upload form" do
    get admin_new_bundle_url(host: "admin.lvh.me")

    assert_response :success
    assert_match "drop-zone", response.body
    assert_match "slug-input", response.body
    assert_match 'data-controller="upload"', response.body
  end

  test "create upload accepts file and stages it" do
    file = Rack::Test::UploadedFile.new(StringIO.new("# Test"), "text/markdown", true, original_filename: "test.md")

    post admin_uploads_url(host: "admin.lvh.me"),
      params: {
        slug: "test-bundle",
        source_kind: "file",
        original_filename: "test.md",
        access_mode: "public",
        replace_existing: false,
        file: file
      }

    assert_response :created
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "test-bundle", json["slug"]

    upload = BundleUpload.find(json["id"])
    assert_equal "staged", upload.status
    assert upload.byte_size > 0
  end

  test "upload requires authentication" do
    reset!
    host! "admin.lvh.me"

    get admin_new_bundle_url(host: "admin.lvh.me")

    assert_redirected_to admin_login_url(host: "admin.lvh.me")
  end

  private

  def github_auth(uid:, login:)
    OmniAuth::AuthHash.new(
      provider: "github",
      uid:,
      info: {
        nickname: login,
        name: login.capitalize,
        image: "https://example.com/#{login}.png"
      }
    )
  end
end
