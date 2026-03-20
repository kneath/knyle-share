require "application_system_test_case"

class PublicBundleGateSystemTest < ApplicationSystemTestCase
  setup do
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all

    Bundle.create!(
      slug: "private-brief",
      title: "Private Brief",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern",
      entry_path: "private-brief.pdf"
    )
  end

  test "protected bundles render the password gate and reject a bad password" do
    visit "http://share.lvh.me:4010/private-brief"

    assert_text "This bundle is protected"

    fill_in "Shared password", with: "wrong password"
    click_button "Open bundle"

    assert_text "Password was incorrect."
    assert_text "This bundle is protected"
  end
end
