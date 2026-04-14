class BundleMarkdownRenderer
  VERSION = 2

  GFM_OPTIONS = {
    extension: {
      table: true,
      strikethrough: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      tagfilter: true
    }
  }.freeze

  ALLOWED_TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags + %w[
    table thead tbody tfoot tr th td caption colgroup col input
  ]).freeze

  ALLOWED_ATTRIBUTES = (Rails::HTML5::SafeListSanitizer.allowed_attributes + %w[
    align colspan rowspan scope type checked disabled
  ]).freeze

  def self.render(body)
    new(body:).render
  end

  def initialize(body:)
    @body = body
  end

  def render
    ActionController::Base.helpers.sanitize(
      Commonmarker.to_html(normalized_body, options: GFM_OPTIONS),
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    )
  end

  private

  attr_reader :body

  def normalized_body
    value = body.to_s
    return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

    value.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
