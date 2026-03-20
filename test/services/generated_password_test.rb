require "test_helper"

class GeneratedPasswordTest < ActiveSupport::TestCase
  test "generate returns three lowercase words separated by spaces" do
    password = GeneratedPassword.generate

    assert_match(/\A[a-z]+ [a-z]+ [a-z]+\z/, password)
  end
end
