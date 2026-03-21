class BundleMarkdownRenderer
  VERSION = 1

  def self.render(body)
    new(body:).render
  end

  def initialize(body:)
    @body = body
  end

  def render
    ActionController::Base.helpers.sanitize(Commonmarker.to_html(normalized_body))
  end

  private

  attr_reader :body

  def normalized_body
    value = body.to_s
    return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

    value.dup.force_encoding(Encoding::UTF_8).scrub
  end
end
