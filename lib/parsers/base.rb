# frozen_string_literal: true

module Parsers
  class Base
    PREFIX = 'passenger'

    attr_reader :batch, :xml, :prefix, :tags

    def initialize(batch, xml, prefix: nil, tags: nil)
      @batch = batch
      @xml = xml
      @prefix = prefix
      @tags = tags
    end

    protected

    def gauge(xml_key, key)
      # Strip before the emptiness check: a pretty-printed element that holds
      # only whitespace carries no value, and forwarding "  " to Datadog would
      # record a bogus zero rather than nothing at all.
      value = xml.xpath(xml_key).text.strip
      return if value.empty?

      if tags
        batch.gauge(key_for(key), value, tags: tags)
      else
        batch.gauge(key_for(key), value)
      end
    end

    def key_for(key)
      [PREFIX, prefix, key].compact.join('.')
    end
  end
end
