# frozen_string_literal: true

require 'nokogiri'
require 'datadog/statsd'

require 'parsers/base'
require 'parsers/root'
require 'parsers/group'
require 'parsers/process'

class PassengerDatadog
  def run
    status = strip_header(collect)
    return if status.nil?

    statsd = Datadog::Statsd.new(single_thread: true, buffer_max_pool_size: 1)
    begin
      run_parsers(statsd, Nokogiri::XML(status))
    ensure
      # Closing releases the socket; skipping it on a parser error would leak one
      # file descriptor per collection run for the life of the service.
      statsd.close
    end
  end

  private

  def collect
    status = `passenger-status --show=xml`
    return status unless status.empty?

    # Usually a PATH problem under systemd rather than an idle Passenger, and
    # silence here makes a misconfigured service look healthy.
    warn('passenger-status produced no output; skipping this collection run')
    nil
  end

  # Good job Passenger 4.0.10. Return non xml in your xml output. Look for the
  # declaration rather than dropping a fixed number of lines: passenger-status
  # can also print a short error to stdout, and dropping three lines from that
  # leaves nothing to parse.
  def strip_header(status)
    return nil if status.nil?
    return status if status.start_with?('<?xml')

    lines = status.lines
    index = lines.index { |line| line.start_with?('<?xml') }
    if index.nil?
      warn("passenger-status produced no XML; skipping this collection run: #{lines.first&.strip}")
      return nil
    end

    lines[index..].join
  end

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
