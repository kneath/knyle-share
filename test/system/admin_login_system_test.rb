require "application_system_test_case"

class AdminLoginSystemTest < ApplicationSystemTestCase
  setup do
    Installation.delete_all
    Installation.create!(
      admin_github_uid: "12345",
      admin_github_login: "kneath",
      admin_github_name: "Kyle Neath",
      admin_claimed_at: Time.current
    )
  end

  test "claimed installations send the admin host root to login" do
    visit "http://admin.lvh.me:4010/"

    assert_current_path "/login"
    assert_text "Admin access only"
    assert_link "Sign in with GitHub"
  end
end
