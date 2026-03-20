require "test_helper"

class BundleTest < ActiveSupport::TestCase
  test "protected bundles require a password digest" do
    bundle = Bundle.new(
      slug: "protected-bundle",
      title: "Protected Bundle",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "protected",
      status: "active"
    )

    assert_not bundle.valid?
    assert_includes bundle.errors[:password_digest], "must be set for protected bundles"
  end

  test "reserved slugs are rejected" do
    bundle = build_bundle(slug: "api")

    assert_not bundle.valid?
    assert_includes bundle.errors[:slug], "is reserved"
  end

  private

  def build_bundle(**attributes)
    defaults = {
      slug: "sample-bundle",
      title: "Sample Bundle",
      source_kind: "file",
      presentation_kind: "single_download",
      access_mode: "public",
      status: "active"
    }

    Bundle.new(defaults.merge(attributes))
  end
end
