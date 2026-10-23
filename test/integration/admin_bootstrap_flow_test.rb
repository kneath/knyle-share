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
    assert_select "form[action='/auth/github'][method='post'][data-turbo='false'] button.btn.btn-github"
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

  test "login page starts GitHub sign-in with a CSRF-protected POST" do
    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))

    with_forgery_protection { get admin_login_url(host: "admin.lvh.me") }

    assert_response :success
    assert_select "form[action='/auth/github'][method='post'][data-turbo='false']" do
      assert_select "input[name='authenticity_token']"
      assert_select "button.btn.btn-github", text: "Sign in with GitHub"
    end
    assert_select "a[href='/auth/github']", 0
  end

  test "GitHub sign-in cannot be started with a GET" do
    OmniAuth.config.test_mode = false

    get "/auth/github"

    assert_response :not_found
  end

  test "GitHub sign-in rejects a POST without a valid CSRF token" do
    OmniAuth.config.test_mode = false

    with_forgery_protection { post "/auth/github" }

    assert_response :redirect
    assert_match %r{/auth/failure\?message=}, response.location
    assert_no_match %r{github\.com}, response.location
  end

  test "GitHub sign-in redirects to GitHub for a POST with a valid CSRF token" do
    OmniAuth.config.test_mode = false
    Installation.current.claim_from_auth!(github_auth(uid: "12345", login: "kneath"))

    with_forgery_protection do
      get admin_login_url(host: "admin.lvh.me")
      token = css_select("form[action='/auth/github'] input[name='authenticity_token']").first["value"]
      post "/auth/github", params: { authenticity_token: token }
    end

    assert_response :redirect
    assert_match %r{\Ahttps://github\.com/login/oauth/authorize\?}, response.location
  end

  private

  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

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
