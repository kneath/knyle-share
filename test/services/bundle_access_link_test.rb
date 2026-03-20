require "test_helper"

class BundleAccessLinkTest < ActiveSupport::TestCase
  test "generated links verify against the original bundle" do
    bundle = Bundle.create!(
      slug: "poke-recipes",
      title: "Poke Recipes",
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "protected",
      status: "active",
      password: "river maple lantern"
    )

    token = BundleAccessLink.generate(bundle:, expires_in: 1.day)
    payload = BundleAccessLink.verify(token)

    assert_equal bundle.id, payload[:bundle_id]
    assert_equal bundle.slug, payload[:slug]
    assert payload[:expires_at].future?
  end
end
