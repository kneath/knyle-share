require "test_helper"

class BundleIngest::PublishedStorageKeyTest < ActiveSupport::TestCase
  test "builds a published storage key from the bundle revision" do
    bundle = Bundle.new(id: 42, content_revision: 7)

    key = BundleIngest::PublishedStorageKey.call(bundle:, path: "assets/app.css")

    assert_equal "bundles/42/7/assets/app.css", key
  end

  test "rejects path traversal" do
    bundle = Bundle.new(id: 42, content_revision: 7)

    assert_raises(BundleIngest::PublishedStorageKey::InvalidPathError) do
      BundleIngest::PublishedStorageKey.call(bundle:, path: "../secrets.txt")
    end
  end
end
