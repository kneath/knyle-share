require "application_system_test_case"

class PublicStaticBundleSystemTest < ApplicationSystemTestCase
  setup do
    BundleUniqueViewer.delete_all
    BundleView.delete_all
    ViewerSession.delete_all
    BundleAsset.delete_all
    Bundle.delete_all

    @bundle = Bundle.create!(
      slug: "design-review",
      title: "Design Review",
      source_kind: "directory",
      presentation_kind: "static_site",
      access_mode: "public",
      status: "active",
      entry_path: "index.html"
    )
    @bundle.assets.create!(
      path: "index.html",
      storage_key: "bundles/#{@bundle.id}/1/index.html",
      content_type: "text/html",
      byte_size: 1024
    )
  end

  test "shared-host static bundle URLs redirect into the isolated bundle subdomain" do
    with_stubbed_storage("index.html" => "<h1>Design Review</h1>") do
      visit "http://share.lvh.me:4010/design-review"

      assert_text "Design Review"
      assert_equal "http://design-review.share.lvh.me:4010/", page.current_url
    end
  end

  private

  def with_stubbed_storage(contents)
    fake_storage = Struct.new(:contents) do
      def read(asset)
        raise BundleStorage::MissingObjectError, asset.path unless contents.key?(asset.path)

        contents.fetch(asset.path)
      end

      def fetch(asset)
        {
          body: read(asset),
          content_type: asset.content_type,
          filename: File.basename(asset.path)
        }
      rescue BundleStorage::MissingObjectError
        raise BundleStorage::MissingObjectError, asset.path
      end

      def download_url(asset, disposition:, expires_in: 5.minutes)
        "https://downloads.example.test/#{asset.path}?disposition=#{disposition}"
      end

      def render_markdown_inline?(asset)
        true
      end
    end.new(contents)

    BundleStorage.stub :new, fake_storage do
      yield
    end
  end
end
