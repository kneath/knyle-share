class GeneratedPassword
  WORDS = %w[
    amber
    anchor
    apricot
    atlas
    banner
    basil
    beacon
    birch
    cedar
    cinder
    clover
    cobalt
    coral
    harbor
    hazel
    heather
    juniper
    lantern
    maple
    marigold
    meadow
    moss
    pebble
    river
    saffron
    sparrow
    spruce
    summit
    thicket
    willow
  ].freeze

  def self.generate
    new.generate
  end

  def generate
    Array.new(3) { WORDS[SecureRandom.random_number(WORDS.length)] }.join(" ")
  end
end
