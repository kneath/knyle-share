require "test_helper"

class AdminBundleManagementTest < ActionDispatch::IntegrationTest
  setup do
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all
    Installation.delete_all

    host! "admin.lvh.me"

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "12345", login: "kneath")

    @protected_bundle = Bundle.create!(
      slug: "poke-recipes",
      title: "Poke Recipes",
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern",
      byte_size: 2.4.megabytes.to_i,
      asset_count: 0,
      total_views_count: 12,
      unique_protected_viewers_count: 4,
      last_viewed_at: 2.hours.ago,
      entry_path: "index.html"
    )
    @protected_bundle.assets.create!(
      path: "index.html",
      storage_key: "bundles/#{@protected_bundle.id}/1/index.html",
      content_type: "text/html",
      byte_size: 1024
    )

    @public_bundle = Bundle.create!(
      slug: "old-mockups",
      title: "Old Mockups",
      source_kind: "directory",
      presentation_kind: "file_listing",
      access_mode: "public",
      status: "disabled",
      byte_size: 12.megabytes,
      asset_count: 0,
      total_views_count: 0,
      unique_protected_viewers_count: 0,
      entry_path: "index.txt"
    )
    @public_bundle.assets.create!(
      path: "files/mockup-1.png",
      storage_key: "bundles/#{@public_bundle.id}/1/files/mockup-1.png",
      content_type: "image/png",
      byte_size: 2048
    )

    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))
    get "/auth/github/callback"
    follow_redirect!
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "bundle index renders real records" do
    get admin_bundles_url(host: "admin.lvh.me")

    assert_response :success
    assert_match "Poke Recipes", response.body
    assert_match "old-mockups", response.body
  end

  test "bundle status toggles" do
    patch admin_bundle_status_url(@protected_bundle, host: "admin.lvh.me")

    assert_redirected_to admin_bundle_url(@protected_bundle, host: "admin.lvh.me")
    assert_equal "disabled", @protected_bundle.reload.status
  end

  test "password rotation generates a new password" do
    old_digest = @protected_bundle.password_digest

    patch admin_bundle_password_url(@protected_bundle, host: "admin.lvh.me"), params: { password_strategy: "generated" }

    assert_redirected_to admin_bundle_url(@protected_bundle, host: "admin.lvh.me")
    follow_redirect!

    assert_response :success
    assert_not_equal old_digest, @protected_bundle.reload.password_digest
    assert_match(/\A.*[a-z]+ [a-z]+ [a-z]+.*\z/m, response.body)
  end

  test "signed link generation renders a tokenized url" do
    post admin_bundle_link_url(@protected_bundle, host: "admin.lvh.me"), params: { expires_in: "1_week" }

    assert_response :success
    assert_match "share.lvh.me/poke-recipes?access=", response.body
  end

  test "bundle deletion removes the record" do
    assert_difference("Bundle.count", -1) do
      delete admin_bundle_url(@public_bundle, host: "admin.lvh.me")
    end

    assert_redirected_to admin_bundles_url(host: "admin.lvh.me")
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
