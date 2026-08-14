# frozen_string_literal: true

require 'spec_helper'

# `s.files` is built from `git ls-files`, so a file that exists on disk but was
# never `git add`ed silently disappears from the built gem.
describe 'the gemspec' do
  subject(:gemspec) { Gem::Specification.load(File.expand_path('../passenger_datadog.gemspec', __dir__)) }

  let(:tracked) { Dir.glob('{bin,lib}/**/*').select { |path| File.file?(path) } }

  it 'packages every runtime file' do
    expect(gemspec.files).to include(*tracked)
  end

  it 'packages the executable' do
    expect(gemspec.executables).to eq(['passenger-datadog'])
  end

  # docs/ is deliberately repo-only; shipping it would bloat the gem.
  it 'ships no documentation directory' do
    expect(gemspec.files.grep(%r{^docs/})).to be_empty
  end

  it 'declares only the three runtime dependencies' do
    expect(gemspec.runtime_dependencies.map(&:name)).to contain_exactly('dogstatsd-ruby', 'nokogiri', 'passenger')
  end

  # Development dependencies live in the Gemfile, so installing the gem does not
  # drag rspec and rubocop onto a production host.
  it 'declares no development dependencies' do
    expect(gemspec.development_dependencies).to be_empty
  end

  it 'requires the supported ruby' do
    expect(gemspec.required_ruby_version.to_s).to eq('>= 3.3.0')
  end
end
