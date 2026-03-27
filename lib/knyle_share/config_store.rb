require "fileutils"
require "json"

module KnyleShare
  class ConfigStore
    def initialize(env: ENV, default_config_name: "config.json")
      @env = env
      @default_config_name = default_config_name
    end

    def load
      persisted = File.exist?(path) ? JSON.parse(File.read(path)) : {}

      {
        admin_url: present(env["KNYLE_SHARE_ADMIN_URL"]) || persisted["admin_url"],
        api_token: present(env["KNYLE_SHARE_API_TOKEN"]) || persisted["api_token"]
      }
    end

    def save(admin_url:, api_token:)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate({ admin_url:, api_token: }) + "\n")
      File.chmod(0o600, path)
      path
    end

    def path
      env["KNYLE_SHARE_CONFIG"] || File.join(config_root, "knyle-share", @default_config_name)
    end

    private

    attr_reader :env

    def config_root
      present(env["XDG_CONFIG_HOME"]) || File.join(Dir.home, ".config")
    end

    def present(value)
      candidate = value.to_s.strip
      candidate.empty? ? nil : candidate
    end
  end
end
