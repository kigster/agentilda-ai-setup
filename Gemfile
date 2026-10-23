# frozen_string_literal: true

source "https://rubygems.org"

gem "rake"
gem "yard"
gem "colored2"
gem "dupervisor"

group :development do
  gem "standard" # standard is rubocop with the arguing removed
end

group :test do
  gem "coverage-badge"
  gem "json_schemer" # validates configuration.example.yml against configuration.schema.json
  gem "rspec"
  gem "rspec-its"
  gem "rspec_junit_formatter" # JUnit XML for CircleCI store_test_results
  gem "simplecov"
end
