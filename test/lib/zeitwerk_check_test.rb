require "test_helper"
require "open3"
require "rbconfig"

class ZeitwerkCheckTest < ActiveSupport::TestCase
  # Eager loading only happens in production, so autoload naming violations
  # (like a lib file defining VERSION where Zeitwerk expects Version) boot the
  # deployed app into a crash loop while every local test stays green. This
  # runs the same check production performs, before a deploy can find it.
  test "zeitwerk check passes so production eager loading cannot crash" do
    stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "test" },
      RbConfig.ruby,
      Rails.root.join("bin/rails").to_s,
      "zeitwerk:check",
      chdir: Rails.root.to_s
    )

    assert_predicate status, :success?, "zeitwerk:check failed:\n#{stdout}\n#{stderr}"
  end
end
