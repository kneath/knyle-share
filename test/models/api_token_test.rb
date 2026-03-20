require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "issue returns a persisted record and plaintext token" do
    token, plaintext = ApiToken.issue!(label: "CLI")

    assert_predicate token, :persisted?
    assert_equal 40, plaintext.length
    assert_equal token, ApiToken.authenticate(plaintext)
  end

  test "revoked tokens no longer authenticate" do
    token, plaintext = ApiToken.issue!(label: "CLI")
    token.revoke!

    assert_nil ApiToken.authenticate(plaintext)
  end
end
