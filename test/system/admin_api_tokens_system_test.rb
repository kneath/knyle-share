require "application_system_test_case"

class AdminApiTokensSystemTest < ApplicationSystemTestCase
  setup do
    ApiToken.delete_all
    Installation.delete_all

    Installation.create!(
      admin_github_uid: "12345",
      admin_github_login: "kneath",
      admin_github_name: "Kyle Neath",
      admin_claimed_at: Time.current
    )

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "12345",
      info: {
        nickname: "kneath",
        name: "Kyle Neath",
        image: "https://example.com/kneath.png"
      }
    )
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "admin creates and revokes a token from the admin ui" do
    visit "http://admin.lvh.me:4010/auth/github/callback"
    assert_current_path "/bundles"

    click_link "API Tokens"
    assert_current_path "/api-tokens"

    fill_in "Label", with: "MacBook CLI"
    click_button "Create API token"

    assert_text "API token created. Copy it now. You will not be able to see it again."
    assert_text "MacBook CLI"
    assert_text "New token"

    click_button "Revoke"

    assert_text "Revoked MacBook CLI."
    assert_text "Revoked"
  end
end
