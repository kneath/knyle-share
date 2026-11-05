require "test_helper"

class AdminApiTokensTest < ActionDispatch::IntegrationTest
  setup do
    ApiToken.delete_all
    Installation.delete_all

    host! "admin.lvh.me"

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "12345", login: "kneath")

    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))
    get "/auth/github/callback"
    follow_redirect!
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "admin can create a token from the ui" do
    post admin_api_tokens_url(host: "admin.lvh.me"), params: { api_token: { label: "MacBook CLI" } }

    assert_response :created
    assert_match "API token created", response.body
    assert_match "MacBook CLI", response.body
    assert_match(/\b[A-Za-z0-9]{40}\b/, response.body)
    assert_equal [ "MacBook CLI" ], ApiToken.pluck(:label)
  end

  test "admin can create a token limited to a slug prefix" do
    post admin_api_tokens_url(host: "admin.lvh.me"), params: { api_token: { label: "Knylebot", slug_prefix: "kb-" } }

    assert_response :created
    assert_match "Only <code>kb-*</code> bundles", response.body
    assert_equal "kb-", ApiToken.find_by!(label: "Knylebot").slug_prefix
  end

  test "tokens created without a slug prefix are unrestricted" do
    post admin_api_tokens_url(host: "admin.lvh.me"), params: { api_token: { label: "MacBook CLI", slug_prefix: "" } }

    assert_response :created
    assert_match "All bundles", response.body
    assert_nil ApiToken.find_by!(label: "MacBook CLI").slug_prefix
  end

  test "admin sees an error for a malformed slug prefix" do
    post admin_api_tokens_url(host: "admin.lvh.me"), params: { api_token: { label: "Knylebot", slug_prefix: "kb" } }

    assert_response :unprocessable_entity
    assert_match "Slug prefix must be lowercase letters, numbers, and hyphens, ending in a hyphen", response.body
    assert_empty ApiToken.all
  end

  test "admin can revoke an existing token" do
    api_token, = ApiToken.issue!(label: "CI upload")

    patch admin_revoke_api_token_url(api_token, host: "admin.lvh.me")

    assert_redirected_to admin_api_tokens_url(host: "admin.lvh.me")
    assert api_token.reload.revoked_at.present?
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
