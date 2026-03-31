require "test_helper"

class BundleMarkdownRendererTest < ActiveSupport::TestCase
  test "renders basic markdown to html" do
    html = BundleMarkdownRenderer.render("# Hello\n\nWorld")

    assert_includes html, "<h1>"
    assert_includes html, "Hello"
    assert_includes html, "<p>"
    assert_includes html, "World"
  end

  test "strips script tags" do
    html = BundleMarkdownRenderer.render('<script>alert("xss")</script>')

    assert_no_match "<script", html
    assert_no_match "alert", html
  end

  test "strips event handler attributes" do
    html = BundleMarkdownRenderer.render('<div onclick="alert(1)">click me</div>')

    assert_no_match "onclick", html
    assert_no_match "alert", html
  end

  test "strips iframe tags" do
    html = BundleMarkdownRenderer.render('<iframe src="https://evil.example.com"></iframe>')

    assert_no_match "<iframe", html
  end

  test "strips object and embed tags" do
    html = BundleMarkdownRenderer.render('<object data="exploit.swf"></object><embed src="exploit.swf">')

    assert_no_match "<object", html
    assert_no_match "<embed", html
  end

  test "strips form tags" do
    html = BundleMarkdownRenderer.render('<form action="https://evil.example.com"><input type="text"></form>')

    assert_no_match "<form", html
    assert_no_match "<input", html
  end

  test "strips style tags" do
    html = BundleMarkdownRenderer.render('<style>body { display: none; }</style>')

    assert_no_match "<style", html
  end

  test "strips javascript protocol in links" do
    html = BundleMarkdownRenderer.render('[click me](javascript:alert(1))')

    assert_no_match "javascript:", html
  end

  test "preserves markdown formatting" do
    html = BundleMarkdownRenderer.render("Hello **world** and *emphasis*")

    assert_includes html, "<strong>world</strong>"
    assert_includes html, "<em>emphasis</em>"
  end

  test "preserves safe links" do
    html = BundleMarkdownRenderer.render("[example](https://example.com)")

    assert_includes html, 'href="https://example.com"'
    assert_includes html, "example"
  end

  test "handles ascii-8bit encoded input" do
    body = "# Hello".dup.force_encoding(Encoding::ASCII_8BIT)
    html = BundleMarkdownRenderer.render(body)

    assert_includes html, "Hello"
  end

  test "scrubs invalid utf-8 sequences" do
    body = "# Valid \xFF\xFE invalid"
    html = BundleMarkdownRenderer.render(body)

    assert_includes html, "Valid"
    assert_not_includes html, "\xFF"
  end
end
