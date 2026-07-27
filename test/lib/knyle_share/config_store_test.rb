require "test_helper"
require "tmpdir"
require_relative "../../../lib/knyle_share/config_store"

class KnyleShareConfigStoreTest < ActiveSupport::TestCase
  test "malformed json names the config path and suggests logging in again" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.json")
      File.write(config_path, "{not json")
      store = KnyleShare::ConfigStore.new(env: { "KNYLE_SHARE_CONFIG" => config_path })

      error = assert_raises(KnyleShare::Error) { store.load }

      assert_includes error.message, config_path
      assert_includes error.message, "invalid JSON"
      assert_includes error.message, "login"
    end
  end
end
