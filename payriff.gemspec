# frozen_string_literal: true

require_relative "lib/payriff/version"

Gem::Specification.new do |spec|
  spec.name = "payriff"
  spec.version = Payriff::VERSION
  spec.summary = "Ruby client for the Payriff merchant API"
  spec.description = "Orders, direct card payments, saved cards, transactions, payouts and invoices for Payriff merchants."
  spec.homepage = "https://github.com/payriff/payriff-ruby"
  spec.license = "MIT"
  spec.authors = ["Payriff"]
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]
  spec.metadata = {
    "source_code_uri" => "https://github.com/payriff/payriff-ruby",
    "changelog_uri" => "https://github.com/payriff/payriff-ruby/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
end