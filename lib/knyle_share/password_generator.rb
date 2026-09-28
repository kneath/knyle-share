require "securerandom"

module KnyleShare
  class PasswordGenerator
    # 16 random bytes provide 128 bits of entropy. URL-safe characters are easy
    # to copy and use consistently in the CLI, browser, and admin interface.
    def self.generate
      SecureRandom.urlsafe_base64(16)
    end
  end
end
