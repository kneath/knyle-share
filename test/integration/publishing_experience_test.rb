require "test_helper"
require_relative "../support/memory_object_store"

class PublishingExperienceTest < ActionDispatch::IntegrationTest
  setup do
    Installation.delete_all
    Installation.create!(admin_github_uid: "audit-admin", admin_github_login: "audit", admin_claimed_at: Time.current)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(provider: "github", uid: "audit-admin", info: { nickname: "audit" })
    host! "admin.lvh.me"
    get "/auth/github/callback"
    @store = MemoryObjectStore.new
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "invalid addresses return actionable json before storing files" do
    ["UPPER", "a" * 64, "api", ""].each do |slug|
      assert_no_difference "BundleUpload.count" do
        post "/uploads", params: upload_params.merge(slug:), headers: { "Accept" => "application/json" }
      end
      assert_response :unprocessable_entity
      assert_equal "application/json", response.media_type
      assert response.parsed_body["error"].present?
    end
  end

  test "existing address is rejected before transfer and replacement is explicit" do
    bundle = make_bundle
    assert_no_difference "BundleUpload.count" do
      post "/uploads", params: upload_params.merge(slug: bundle.slug)
    end
    assert_response :conflict
    get "/uploads/availability", params: { slug: bundle.slug }
    assert_equal true, response.parsed_body["exists"]
    get "/bundles/new", params: { replace: bundle.slug }
    assert_select "input#slug-input[readonly]"
  end

  test "publication is queued and repeated process requests publish only once" do
    BundleIngest::ObjectStore.stub :new, @store do
      post "/uploads", params: upload_params.merge(file: fixture_file)
      assert_response :created
      id = response.parsed_body.fetch("id")
      assert_enqueued_with(job: ProcessBundleUploadJob, args: [id]) { post "/uploads/#{id}/process" }
      assert_response :accepted
      assert_equal "queued", response.parsed_body["status"]
      assert_no_enqueued_jobs { post "/uploads/#{id}/process" }
      ProcessBundleUploadJob.perform_now(id)
      assert_difference("Bundle.count", 0) { post "/uploads/#{id}/process" }
      assert_equal "ready", response.parsed_body["status"]
      assert_match "experience-notes.share.lvh.me", response.parsed_body["public_url"]
      get "/uploads/#{id}"
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  test "cancel prevents a staged upload from publishing" do
    BundleIngest::ObjectStore.stub :new, @store do
      post "/uploads", params: upload_params.merge(file: fixture_file)
      id = response.parsed_body.fetch("id")
      delete "/uploads/#{id}"
      assert_equal "canceled", response.parsed_body["status"]
      assert_no_difference "Bundle.count" do
        post "/uploads/#{id}/process"
        assert_response :conflict
      end
    end
  end

  test "title and visibility edits preserve address and invalidate previous access" do
    bundle = make_bundle
    patch "/bundles/#{bundle.slug}", params: { bundle: { title: "A clearer title", description: "A useful description", access_mode: "protected" } }
    assert_redirected_to "/bundles/#{bundle.slug}"
    bundle.reload
    assert_equal "A clearer title", bundle.title
    assert_equal "experience-existing", bundle.slug
    assert bundle.protected_access?
    assert_equal 2, bundle.access_revision
    follow_redirect!
    assert_select "input#new-password[value]"
    patch "/bundles/#{bundle.slug}", params: { bundle: { access_mode: "public" } }
    assert_nil bundle.reload.password_digest
    assert_equal 3, bundle.access_revision
  end

  test "search filters and pagination bound the library response" do
    27.times { |n| make_bundle(slug: "experience-#{n}", title: "Field notes #{n}") }
    make_bundle(slug: "experience-private", access_mode: "protected", password: "test password")
    get "/bundles", params: { q: "Field notes", access: "public" }
    assert_select ".library-row", 25
    assert_select "nav.pagination", 1
    get "/bundles", params: { q: "Field notes", access: "public", page: 2 }
    assert_select ".library-row", 2
  end

  test "deletion records storage removal durably" do
    bundle = make_bundle
    bundle.assets.create!(path: "test.txt", storage_key: "published/test.txt", byte_size: 4, content_type: "text/plain")
    assert_difference "StorageCleanup.count", 1 do
      delete "/bundles/#{bundle.slug}"
    end
    assert_nil Bundle.find_by(id: bundle.id)
    assert_includes StorageCleanup.last.object_keys, "published/test.txt"
  end

  test "disabled bundles cannot issue signed links" do
    bundle = make_bundle(access_mode: "protected", password: "secret", status: "disabled")
    post "/bundles/#{bundle.slug}/link", params: { expires_in: "1_week" }
    assert_redirected_to "/bundles/#{bundle.slug}"
  end

  test "expired admin session returns json without silently following login" do
    reset!
    host! "admin.lvh.me"
    get "/uploads/availability", params: { slug: "example" }, headers: { "Accept" => "application/json" }
    assert_response :unauthorized
    assert_match "Sign in", response.parsed_body["error"]
  end

  private

  def upload_params
    { slug: "experience-notes", source_kind: "file", original_filename: "notes.md", access_mode: "public", replace_existing: false }
  end

  def fixture_file
    Rack::Test::UploadedFile.new(StringIO.new("# Field notes"), "text/markdown", true, original_filename: "notes.md")
  end

  def make_bundle(**attributes)
    Bundle.create!({ slug: "experience-existing", title: "Existing", source_kind: "file", presentation_kind: "single_download", access_mode: "public", status: "active" }.merge(attributes))
  end
end
