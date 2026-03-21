require "test_helper"
require_relative "../../../lib/knyle_share/cli"

class KnyleShareCliTest < ActiveSupport::TestCase
  test "defines the Zeitwerk-compatible cli constant" do
    assert_equal KnyleShare::Cli, KnyleShare::CLI
  end
end
