# frozen_string_literal: true

require 'nokogiri'
require 'datadog/statsd'

require 'parsers/base'
require 'parsers/root'
require 'parsers/group'
require 'parsers/process'

class PassengerDatadog
  def run
    status = `passenger-status --show=xml`
    if status.empty?
      # Usually a PATH problem under systemd rather than an idle Passenger, and
      # silence here makes a misconfigured service look healthy.
      warn('passenger-status produced no output; skipping this collection run')
      return
    end

    # Good job Passenger 4.0.10. Return non xml in your xml output.
    status = status.split("\n")[3..].join("\n") unless status.start_with?('<?xml')

    statsd = Datadog::Statsd.new(single_thread: true, buffer_max_pool_size: 1)
    parsed = Nokogiri::XML(status)

    run_parsers(statsd, parsed)
    statsd.close
  end

  private

  def run_parsers(statsd, parsed)
    Parsers::Root.new(statsd, parsed.xpath('//info')).run

    multiple_supergroups = parsed.xpath('//supergroups/supergroup').count > 1
    parsed.xpath('//supergroups/supergroup').each do |supergroup|
      prefix = multiple_supergroups ? normalize_prefix(supergroup.xpath('name').text) : nil
      Parsers::Group.new(statsd, supergroup.xpath('group'), prefix: prefix).run

      supergroup.xpath('group/processes/process').each_with_index do |process, index|
        Parsers::Process.new(statsd, process, prefix: prefix, tags: ["passenger-process:#{index}"]).run
      end
    end
  end

  def normalize_prefix(prefix)
    prefix.gsub(/(-|\s)/, '_').gsub(/(\W|\d)/i, '')
  end
end
