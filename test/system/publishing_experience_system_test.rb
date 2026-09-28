require "application_system_test_case"
require_relative "../support/memory_object_store"

class PublishingExperienceSystemTest < ApplicationSystemTestCase
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all
    BundleUpload.delete_all
    StorageCleanup.delete_all
    Installation.delete_all
    Installation.create!(admin_github_uid: "system-audit", admin_github_login: "audit", admin_claimed_at: Time.current)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: "github", uid: "system-audit", info: { nickname: "audit" })
    @store = MemoryObjectStore.new
    visit "http://admin.lvh.me:4010/auth/github/callback"
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "protected publishing exposes the password and public selection hides its controls" do
    BundleIngest::ObjectStore.stub :new, @store do
      perform_enqueued_jobs do
        click_link "New bundle"
        assert_selector 'input[name="access_mode"][value="protected"]', visible: true
        find('input[name="access_mode"][value="protected"]').send_keys(:arrow_right)
        assert_checked_field "Public"
        assert_no_text "A generated password will be shown"
        choose "Protected", exact: true
        assert_text "A generated password will be shown"
        Tempfile.create(["field-notes", ".md"]) do |file|
          file.write("# A shared document"); file.flush
          attach_file file.path, make_visible: true
          fill_in "Link address", with: "system-publishing"
          click_button "Upload", exact: true
          assert_text "Ready to share", wait: 15
          secret = find("#ready-password").value
          assert_match(/\A[A-Za-z0-9_-]{22}\z/, secret)
          assert Bundle.find_by!(slug: "system-publishing").authenticate(secret)
          assert_equal "http://system-publishing.share.lvh.me:4010/", find("#ready-url").value
          assert_text "Copy sharing details"
        end
      end
    end
  end

  test "mobile layouts contain long content in light and dark themes" do
    bundle = Bundle.create!(slug: "a" * 63, title: "A" * 120, source_kind: "file", presentation_kind: "single_download", access_mode: "public")
    browser = page.driver.browser
    ["light", "dark"].each do |scheme|
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [{ name: "prefers-color-scheme", value: scheme }])
      [320, 390, 768].each do |width|
        browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 844, deviceScaleFactor: 1, mobile: true)
        ["/bundles/#{bundle.slug}", "/api-tokens", "/bundles/new"].each do |path|
          visit "http://admin.lvh.me:4010#{path}"
          assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
        end
      end
      visit "http://admin.lvh.me:4010/bundles/#{bundle.slug}"
      page.save_screenshot(Rails.root.join("tmp/screenshots/audit-#{scheme}.png"))
    end
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
    browser&.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "canceling deletion leaves the bundle and confirming deletes it" do
    bundle = Bundle.create!(slug: "system-delete", title: "Delete fixture", source_kind: "file", presentation_kind: "single_download", access_mode: "public")
    visit "http://admin.lvh.me:4010/bundles/#{bundle.slug}"
    dismiss_confirm { click_button "Delete bundle" }
    assert Bundle.exists?(bundle.id)
    accept_confirm { click_button "Delete bundle" }
    assert_text "Deleted system-delete"
    assert_not Bundle.uncached { Bundle.exists?(bundle.id) }
  end
end
