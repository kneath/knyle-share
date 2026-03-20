class BundleMarkdownRenderer
  VERSION = 1

  def self.render(body)
    new(body:).render
  end

  def initialize(body:)
    @body = body
  end

  def render
    ActionController::Base.helpers.sanitize(Commonmarker.to_html(body.to_s))
  end

  private

  attr_reader :body
end
