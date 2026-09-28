require "test_helper"

class GeneratedPasswordTest < ActiveSupport::TestCase
  test "generate returns a URL-safe password with 128 random bits" do
    password = GeneratedPassword.generate

    assert_match(/\A[A-Za-z0-9_-]{22}\z/, password)
  end
end
