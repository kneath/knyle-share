require "test_helper"

class BundleIngest::ClassificationTest < ActiveSupport::TestCase
  test "classifies a directory with index html as a static site" do
    classification = BundleIngest::Classifier.call(
      source_kind: "directory",
      entries: ["index.html", "assets/app.css", "assets/app.js"]
    )

    assert_equal "static_site", classification.presentation_kind
    assert_equal "directory", classification.source_kind
    assert_equal "index.html", classification.entry_path
  end

  test "classifies a directory without index html as a file listing" do
    classification = BundleIngest::Classifier.call(
      source_kind: "directory",
      entries: [{ path: "notes.txt" }, { path: "images/cover.png" }]
    )

    assert_equal "file_listing", classification.presentation_kind
    assert_nil classification.entry_path
  end

  test "classifies a markdown file as a markdown document" do
    classification = BundleIngest::Classifier.call(
      source_kind: "file",
      entries: ["draft.md"]
    )

    assert_equal "markdown_document", classification.presentation_kind
    assert_equal "draft.md", classification.entry_path
  end

  test "classifies a non-markdown file as a single download" do
    classification = BundleIngest::Classifier.call(
      source_kind: "file",
      entries: ["archive.zip"]
    )

    assert_equal "single_download", classification.presentation_kind
    assert_equal "archive.zip", classification.entry_path
  end
end
