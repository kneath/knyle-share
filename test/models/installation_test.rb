require "test_helper"

class InstallationTest < ActiveSupport::TestCase
  setup do
    Installation.delete_all
  end

  test "current returns an unsaved installation when one does not exist" do
    installation = Installation.current

    assert_predicate installation, :new_record?
    assert_not installation.claimed?
  end

  test "claim_from_auth! stores the github identity" do
    installation = Installation.current
    auth = OmniAuth::AuthHash.new(
      uid: "12345",
      info: {
        nickname: "kneath",
        name: "Kyle Neath",
        image: "https://example.com/avatar.png"
      }
    )

    installation.claim_from_auth!(auth)

    assert installation.persisted?
    assert_equal "12345", installation.admin_github_uid
    assert_equal "kneath", installation.admin_github_login
    assert_equal "Kyle Neath", installation.admin_github_name
    assert_equal "https://example.com/avatar.png", installation.admin_github_avatar_url
    assert installation.admin_claimed_at.present?
  end
end
