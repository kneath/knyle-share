require_relative "lib/knyle_share/version"

Gem::Specification.new do |spec|
  spec.name = "knyle-share"
  spec.version = KnyleShare::VERSION
  spec.authors = ["Knyle Share contributors"]
  spec.summary = "Command-line client for Knyle Share"
  spec.description = "Uploads files and directories to a Knyle Share server."
  spec.homepage = "https://github.com/kneath/knyle-share"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir[
    "lib/knyle_share.rb",
    "lib/knyle_share/**/*.rb",
    "exe/knyle-share",
    "README.md"
  ].sort
  spec.bindir = "exe"
  spec.executables = ["knyle-share"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack"
end
