require "test_helper"

class Public::AccessControllerTest < ActionController::TestCase
  setup do
    @bundle = Bundle.create!(slug: "stale-icon", title: "Private files", source_kind: "directory", presentation_kind: "file_listing", access_mode: "protected", password: "test-password")
    @request.host = "stale-icon.share.lvh.me"
  end

  test "old sessions with missing icon destinations return to the main page" do
    %w[/icon.svg /icon.png?old=1 /favicon.ico /%69con.svg].each do |path|
      session[:bundle_return_to] = path
      post :create, params: { password: "test-password" }
      assert_redirected_to "/"
      assert_nil session[:bundle_return_to]
    end
  end

  test "saved destinations for uploaded icons are preserved" do
    @bundle.assets.create!(path: "icon.svg", storage_key: "site/icon.svg", content_type: "image/svg+xml", byte_size: 20)
    session[:bundle_return_to] = "/icon.svg?download=1"
    post :create, params: { password: "test-password" }
    assert_redirected_to "/icon.svg?download=1"
  end

  test "incorrect passwords retain the saved destination" do
    session[:bundle_return_to] = "/nested/photo.png"
    post :create, params: { password: "wrong" }
    assert_response :unprocessable_entity
    assert_equal "/nested/photo.png", session[:bundle_return_to]
  end
end
