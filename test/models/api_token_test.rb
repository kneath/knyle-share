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

  test "tokens without a slug prefix permit every slug" do
    token, = ApiToken.issue!(label: "CLI")

    assert_nil token.slug_prefix
    assert_not token.slug_scoped?
    assert token.permits_slug?("field-notes")
    assert token.permits_slug?("kb-weekly-report")
  end

  test "tokens with a slug prefix only permit matching slugs" do
    token, = ApiToken.issue!(label: "Knylebot", slug_prefix: "kb-")

    assert token.slug_scoped?
    assert token.permits_slug?("kb-weekly-report")
    assert_not token.permits_slug?("field-notes")
    assert_not token.permits_slug?("kbx-report")
    assert_not token.permits_slug?(nil)
  end

  test "blank slug prefixes are stored as unrestricted" do
    token, = ApiToken.issue!(label: "CLI", slug_prefix: "  ")

    assert_nil token.slug_prefix
  end

  test "slug prefixes must look like the start of a slug and end in a hyphen" do
    [ "kb", "KB-", "-kb-", "kb--", "kb_-", "k b-" ].each do |slug_prefix|
      token = ApiToken.new(label: "Knylebot", token_digest: "digest", slug_prefix:)

      assert_not token.valid?, slug_prefix
      assert token.errors.include?(:slug_prefix), slug_prefix
    end

    [ "kb-", "research-bot-", "a1-b2-" ].each do |slug_prefix|
      token = ApiToken.new(label: "Knylebot", token_digest: "digest", slug_prefix:)

      assert token.valid?, slug_prefix
    end
  end
end
