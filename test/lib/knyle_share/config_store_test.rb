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

  test "save creates the config file owner-only rather than tightening it afterward" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "nested", "config.json")
      store = KnyleShare::ConfigStore.new(env: { "KNYLE_SHARE_CONFIG" => config_path })
      previous_umask = File.umask(0)

      begin
        File.stub :chmod, ->(*) { } do
          store.save(admin_url: "https://admin.example.test", api_token: "secret-token")
        end
      ensure
        File.umask(previous_umask)
      end

      assert_equal 0o600, File.stat(config_path).mode & 0o777
      assert_equal "secret-token", store.load[:api_token]
    end
  end

  test "save tightens an existing world-readable config file" do
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.json")
      File.write(config_path, "{}")
      File.chmod(0o644, config_path)
      store = KnyleShare::ConfigStore.new(env: { "KNYLE_SHARE_CONFIG" => config_path })

      store.save(admin_url: "https://admin.example.test", api_token: "secret-token")

      assert_equal 0o600, File.stat(config_path).mode & 0o777
    end
  end
end
