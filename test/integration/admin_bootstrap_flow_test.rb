require "test_helper"

class AdminBootstrapFlowTest < ActionDispatch::IntegrationTest
  setup do
    Installation.delete_all
    host! "admin.lvh.me"
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = nil
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "root redirects to setup before the admin is claimed" do
    get "/"

    assert_redirected_to admin_setup_url(host: "admin.lvh.me")
  end

  test "setup validation renders passing state when checks succeed" do
    result = successful_validation_result

    SetupValidation.stub :new, -> { validator(result) } do
      post admin_validate_setup_url(host: "admin.lvh.me")
    end

    assert_response :success
    assert_select "a.btn.btn-github[href='/auth/github']"
    assert_match "All 5 checks passed", response.body
  end

  test "first github callback claims the installation after validation passes" do
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "12345", login: "kneath")
    result = successful_validation_result

    SetupValidation.stub :new, -> { validator(result) } do
      get "/auth/github/callback"
    end

    assert_redirected_to admin_bundles_url(host: "admin.lvh.me")
    follow_redirect!

    assert_response :success
    assert_match "Bundles", response.body
    assert_equal "12345", Installation.current.admin_github_uid
  end

  test "non-admin github callback is rejected after claim" do
    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "99999", login: "someone-else")

    get "/auth/github/callback"

    assert_redirected_to admin_login_url(host: "admin.lvh.me")
    follow_redirect!

    assert_response :success
    assert_match "not the configured admin", response.body
  end

  test "claimed installations redirect setup to login without running validation" do
    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))

    SetupValidation.stub :new, -> { raise "validation should not run after claim" } do
      get admin_setup_url(host: "admin.lvh.me")
      assert_redirected_to admin_login_url(host: "admin.lvh.me")

      post admin_validate_setup_url(host: "admin.lvh.me")
    end

    assert_redirected_to admin_login_url(host: "admin.lvh.me")
  end

  test "signed-in admins are redirected away from setup after claim without running validation" do
    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))
    OmniAuth.config.mock_auth[:github] = github_auth(uid: "12345", login: "kneath")
    get "/auth/github/callback"
    assert_redirected_to admin_bundles_url(host: "admin.lvh.me")

    SetupValidation.stub :new, -> { raise "validation should not run after claim" } do
      get admin_setup_url(host: "admin.lvh.me")
      assert_redirected_to admin_bundles_url(host: "admin.lvh.me")

      post admin_validate_setup_url(host: "admin.lvh.me")
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

  def successful_validation_result
    SetupValidation::Result.new(
      checks: [
        SetupValidation::Check.new(key: :environment, label: "Environment variables configured", status: :passed, detail: "ok"),
        SetupValidation::Check.new(key: :database, label: "Database reachable and migrated", status: :passed, detail: "ok"),
        SetupValidation::Check.new(key: :s3_config, label: "S3 configuration present", status: :passed, detail: "ok"),
        SetupValidation::Check.new(key: :s3_bucket, label: "S3 bucket reachable", status: :passed, detail: "ok"),
        SetupValidation::Check.new(key: :s3_round_trip, label: "S3 read/write/delete cycle", status: :passed, detail: "ok")
      ]
    )
  end

  def validator(result)
    Struct.new(:result) do
      def call
        result
      end
    end.new(result)
  end
end
