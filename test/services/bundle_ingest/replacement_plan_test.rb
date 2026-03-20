require "test_helper"

class BundleIngest::ReplacementPlanTest < ActiveSupport::TestCase
  test "replacement plan preserves analytics while revoking prior access grants" do
    bundle = Bundle.new(id: 12, slug: "poke-recipes", content_revision: 3, access_revision: 4)

    plan = BundleIngest::ReplacementPlanner.call(bundle:, replace_existing: true)

    assert_equal 12, plan.bundle_id
    assert_equal "poke-recipes", plan.slug
    assert_equal 3, plan.current_content_revision
    assert_equal 4, plan.next_content_revision
    assert_equal 4, plan.current_access_revision
    assert_equal 5, plan.next_access_revision
    assert_predicate plan, :replacing_existing?
    assert_predicate plan, :preserves_analytics
    assert_not_predicate plan, :preserves_sessions
    assert_not_predicate plan, :preserves_signed_links
    assert_equal "bundles/12/4", plan.published_storage_prefix
  end
end
