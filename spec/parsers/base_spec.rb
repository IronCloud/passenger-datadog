# frozen_string_literal: true

require 'spec_helper'

# The defensive lookups exercised here are what keep one codebase working across
# Passenger 4/5/6 schema drift, so they are covered directly rather than only
# incidentally through the version fixtures.
describe Parsers::Base do
  let(:statsd) { instance_double(Datadog::Statsd) }
  # The parsers are handed an element node, not a document, so the relative
  # lookups they perform only work from `<process>` itself.
  let(:xml) { Nokogiri::XML('<process><cpu>7</cpu><rss></rss><swap>  </swap></process>').at_xpath('/process') }

  subject(:parser) { described_class.new(statsd, xml) }

  def gauge(key, xml_key = key, **options)
    described_class.new(statsd, xml, **options).send(:gauge, xml_key, key)
  end

  describe '#gauge' do
    it 'sends the element value' do
      expect(statsd).to receive(:gauge).with('passenger.cpu', '7')

      gauge('cpu')
    end

    it 'skips an element that is absent from this Passenger version' do
      expect(statsd).not_to receive(:gauge)

      gauge('busyness')
    end

    it 'skips an empty element' do
      expect(statsd).not_to receive(:gauge)

      gauge('rss')
    end

    it 'skips a whitespace-only element' do
      expect(statsd).not_to receive(:gauge)

      gauge('swap')
    end

    it 'omits the tags argument entirely when there are no tags' do
      expect(statsd).to receive(:gauge).with('passenger.cpu', '7')

      gauge('cpu')
    end

    it 'passes tags through when present' do
      expect(statsd).to receive(:gauge).with('passenger.cpu', '7', tags: ['passenger-process:3'])

      gauge('cpu', tags: ['passenger-process:3'])
    end

    it 'maps an xml element onto a differently named metric' do
      expect(statsd).to receive(:gauge).with('passenger.pool.used', '7')

      gauge('pool.used', 'cpu')
    end
  end

  describe '#key_for' do
    it 'namespaces the key under passenger' do
      expect(parser.send(:key_for, 'cpu')).to eq('passenger.cpu')
    end

    it 'inserts the supergroup prefix when there is one' do
      prefixed = described_class.new(statsd, xml, prefix: 'app_production')

      expect(prefixed.send(:key_for, 'cpu')).to eq('passenger.app_production.cpu')
    end
  end
end
