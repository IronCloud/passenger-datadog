# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = 'passenger-datadog'
  s.version = '2.0.0'
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 3.3.0'
  s.authors = ['IronCloud']
  s.description = <<-DESCRIPTION
    A tool for sending Passenger stats to Datadog. A continuation of the
    abandoned passenger_datadog gem by Ryan Rosenblum.
  DESCRIPTION

  s.email = 'hello@ironcloud.co'
  s.files = `git ls-files bin lib LICENSE README.md`.split("\n")
  s.executables = %w[passenger-datadog]
  s.extra_rdoc_files = ['LICENSE', 'README.md']
  s.homepage = 'https://github.com/IronCloud/passenger-datadog'
  s.licenses = ['MIT']
  s.metadata = {
    'rubygems_mfa_required' => 'true',
    'source_code_uri' => 'https://github.com/IronCloud/passenger-datadog',
    'changelog_uri' => 'https://github.com/IronCloud/passenger-datadog/blob/main/CHANGELOG.md',
    'documentation_uri' => 'https://www.rubydoc.info/gems/passenger-datadog'
  }
  s.require_paths = ['lib']
  s.summary = 'A tool for sending Passenger stats to Datadog (continuation of passenger_datadog)'

  s.add_dependency('dogstatsd-ruby', '~> 5.7')
  s.add_dependency('nokogiri', '~> 1.16')
  s.add_dependency('passenger', '~> 6.0')
end
