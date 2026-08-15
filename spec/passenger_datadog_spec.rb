# frozen_string_literal: true

require 'spec_helper'

describe PassengerDatadog do
  let(:Statsd) { double(Datadog::Statsd) }
  let(:statsd) { instance_double(Datadog::Statsd) }
  subject { described_class.new }

  context 'passenger not running' do
    before do
      allow(subject).to receive(:`).and_return('')
      allow(subject).to receive(:warn)
    end

    it 'does not send stats to datadog' do
      expect(Datadog::Statsd).not_to receive(:new)

      subject.run
    end

    # A silent skip here made a service that could not find passenger-status
    # look healthy while shipping zero metrics indefinitely.
    it 'warns so the failure is visible in the journal' do
      expect(subject).to receive(:warn).with(/produced no output/)

      subject.run
    end
  end

  context 'passenger-status prints an error instead of xml' do
    before do
      allow(subject).to receive(:`).and_return("passenger-status: command not found\n")
      allow(subject).to receive(:warn)
    end

    # Shorter than the three header lines Passenger 4 prefixes, which a fixed
    # line-count strip turned into a nil that killed the collection loop.
    it 'does not raise' do
      expect { subject.run }.not_to raise_error
    end

    it 'does not send stats to datadog' do
      expect(Datadog::Statsd).not_to receive(:new)

      subject.run
    end

    it 'warns with the output it got' do
      expect(subject).to receive(:warn).with(/no XML.*command not found/)

      subject.run
    end
  end

  context 'passenger-status output is not parseable xml' do
    before do
      allow(subject).to receive(:`).and_return("<?xml version=\"1.0\"?>\n<info><process_coun")
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)
    end

    it 'sends nothing rather than raising' do
      expect(statsd).not_to receive(:gauge)

      expect { subject.run }.not_to raise_error
    end

    it 'still closes the client' do
      expect(statsd).to receive(:close)

      subject.run
    end
  end

  context 'sending fails partway through a run' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_6_status.xml'))
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:gauge).and_raise(SocketError, 'no route to host')
    end

    # Without this the service leaks one socket per 30-second run.
    it 'closes the client before propagating' do
      expect(statsd).to receive(:close)

      expect { subject.run }.to raise_error(SocketError)
    end
  end

  describe 'supergroup prefixes' do
    def status_for(*names)
      groups = names.map do |name|
        "<supergroup><name>#{name}</name><group><capacity_used>1</capacity_used>" \
          '<processes><process><cpu>1</cpu></process></processes></group></supergroup>'
      end
      '<?xml version="1.0"?><info><process_count>1</process_count>' \
        "<supergroups>#{groups.join}</supergroups></info>"
    end

    before do
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)
      allow(statsd).to receive(:gauge)
    end

    it 'omits the prefix when there is only one supergroup' do
      allow(subject).to receive(:`).and_return(status_for('/var/www/app (production)'))

      expect(statsd).to receive(:gauge).with('passenger.capacity_used', '1')

      subject.run
    end

    # The normalizer strips every non-word character *and every digit*, so a
    # path-shaped supergroup name collapses to its letters. Pinned rather than
    # changed: the mapping is what existing dashboards are built on.
    it 'normalizes a path-shaped name to letters and underscores' do
      allow(subject).to receive(:`).and_return(status_for('/var/www/app (production)', '/var/www/other'))

      expect(statsd).to receive(:gauge).with('passenger.varwwwapp_production.capacity_used', '1')

      subject.run
    end

    it 'strips digits out of the name' do
      allow(subject).to receive(:`).and_return(status_for('app1 staging', 'app2 staging'))

      expect(statsd).to receive(:gauge).with('passenger.app_staging.capacity_used', '1').twice

      subject.run
    end

    # Documented consequence of stripping digits: two supergroups whose names
    # differ only by a digit share one metric name.
    it 'collides when two names normalize the same' do
      allow(subject).to receive(:`).and_return(status_for('app1', 'app2'))

      expect(statsd).to receive(:gauge).with('passenger.app.capacity_used', '1').twice

      subject.run
    end

    # The index restarts per supergroup, so the metric prefix is what keeps the
    # two supergroups' process series apart.
    it 'tags process index per supergroup, not globally' do
      allow(subject).to receive(:`).and_return(status_for('alpha', 'beta'))

      expect(statsd).to receive(:gauge).with('passenger.alpha.cpu', '1', tags: ['passenger-process:0'])
      expect(statsd).to receive(:gauge).with('passenger.beta.cpu', '1', tags: ['passenger-process:0'])

      subject.run
    end
  end

  context 'passenger 4' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_4_status.xml'))
    end

    let(:passenger_status) do
      [['passenger.pool.used', '5'],
       ['passenger.pool.max', '20'],
       ['passenger.request_queue', '0'],

       ['passenger.enabled_process_count', '5'],
       ['passenger.disabling_process_count', '0'],
       ['passenger.disabled_process_count', '0'],

       ['passenger.processed', '149', { tags: ['passenger-process:0'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.rss', '554312', { tags: ['passenger-process:0'] }],
       ['passenger.private_dirty', '548660', { tags: ['passenger-process:0'] }],
       ['passenger.pss', '549560', { tags: ['passenger-process:0'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.real_memory', '548660', { tags: ['passenger-process:0'] }],
       ['passenger.vmsize', '952668', { tags: ['passenger-process:0'] }],

       ['passenger.processed', '273', { tags: ['passenger-process:1'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:1'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:1'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:1'] }],
       ['passenger.rss', '547088', { tags: ['passenger-process:1'] }],
       ['passenger.private_dirty', '541420', { tags: ['passenger-process:1'] }],
       ['passenger.pss', '542326', { tags: ['passenger-process:1'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:1'] }],
       ['passenger.real_memory', '541420', { tags: ['passenger-process:1'] }],
       ['passenger.vmsize', '963948', { tags: ['passenger-process:1'] }],

       ['passenger.processed', '139', { tags: ['passenger-process:2'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:2'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:2'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:2'] }],
       ['passenger.rss', '533704', { tags: ['passenger-process:2'] }],
       ['passenger.private_dirty', '258196', { tags: ['passenger-process:2'] }],
       ['passenger.pss', '394044', { tags: ['passenger-process:2'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:2'] }],
       ['passenger.real_memory', '258196', { tags: ['passenger-process:2'] }],
       ['passenger.vmsize', '887132', { tags: ['passenger-process:2'] }],

       ['passenger.processed', '135', { tags: ['passenger-process:3'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:3'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:3'] }],
       ['passenger.cpu', '1', { tags: ['passenger-process:3'] }],
       ['passenger.rss', '559972', { tags: ['passenger-process:3'] }],
       ['passenger.private_dirty', '284396', { tags: ['passenger-process:3'] }],
       ['passenger.pss', '420259', { tags: ['passenger-process:3'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:3'] }],
       ['passenger.real_memory', '284396', { tags: ['passenger-process:3'] }],
       ['passenger.vmsize', '915564', { tags: ['passenger-process:3'] }],

       ['passenger.processed', '236', { tags: ['passenger-process:4'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:4'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:4'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:4'] }],
       ['passenger.rss', '548696', { tags: ['passenger-process:4'] }],
       ['passenger.private_dirty', '543068', { tags: ['passenger-process:4'] }],
       ['passenger.pss', '543957', { tags: ['passenger-process:4'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:4'] }],
       ['passenger.real_memory', '543068', { tags: ['passenger-process:4'] }],
       ['passenger.vmsize', '964668', { tags: ['passenger-process:4'] }]]
    end

    it 'sends stats to datadog' do
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)

      expect(statsd).not_to receive(:gauge).with('passenger.busyness', anything)
      expect(statsd).not_to receive(:gauge).with('passenger.capacity_used', anything)
      expect(statsd).not_to receive(:gauge).with('passenger.processes_being_spawned', anything)

      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end
  end

  context 'passenger 5' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_5_status.xml'))
    end

    let(:passenger_status) do
      [['passenger.pool.used', '2'],
       ['passenger.pool.max', '5'],
       ['passenger.request_queue', '999'],

       ['passenger.capacity_used', '2'],
       ['passenger.get_wait_list_size', '111'],
       ['passenger.disable_wait_list_size', '0'],
       ['passenger.processes_being_spawned', '0'],
       ['passenger.enabled_process_count', '2'],
       ['passenger.disabling_process_count', '0'],
       ['passenger.disabled_process_count', '0'],

       ['passenger.processed', '2', { tags: ['passenger-process:0'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.busyness', '0', { tags: ['passenger-process:0'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.rss', '409596', { tags: ['passenger-process:0'] }],
       ['passenger.private_dirty', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.pss', '267231', { tags: ['passenger-process:0'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.real_memory', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.vmsize', '812632', { tags: ['passenger-process:0'] }],

       ['passenger.processed', '3', { tags: ['passenger-process:1'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:1'] }],
       ['passenger.busyness', '0', { tags: ['passenger-process:1'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:1'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:1'] }],
       ['passenger.rss', '407972', { tags: ['passenger-process:1'] }],
       ['passenger.private_dirty', '124832', { tags: ['passenger-process:1'] }],
       ['passenger.pss', '265607', { tags: ['passenger-process:1'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:1'] }],
       ['passenger.real_memory', '124832', { tags: ['passenger-process:1'] }],
       ['passenger.vmsize', '812536', { tags: ['passenger-process:1'] }]]
    end

    it 'sends stats to datadog' do
      expect(Datadog::Statsd).to receive(:new).with(single_thread: true, buffer_max_pool_size: 1).and_return(statsd)
      allow(statsd).to receive(:close)

      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end
  end

  context 'passenger 6' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_6_status.xml'))
    end

    let(:passenger_status) do
      [['passenger.pool.used', '1'],
       ['passenger.pool.max', '6'],
       ['passenger.request_queue', '0'],

       ['passenger.capacity_used', '1'],
       ['passenger.get_wait_list_size', '0'],
       ['passenger.disable_wait_list_size', '0'],
       ['passenger.processes_being_spawned', '0'],
       ['passenger.enabled_process_count', '1'],
       ['passenger.disabling_process_count', '0'],
       ['passenger.disabled_process_count', '0'],

       ['passenger.processed', '6', { tags: ['passenger-process:0'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.busyness', '0', { tags: ['passenger-process:0'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.rss', '28096', { tags: ['passenger-process:0'] }],
       ['passenger.private_dirty', '3168', { tags: ['passenger-process:0'] }],
       ['passenger.pss', '13731', { tags: ['passenger-process:0'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.real_memory', '3168', { tags: ['passenger-process:0'] }],
       ['passenger.vmsize', '623336', { tags: ['passenger-process:0'] }]]
    end

    it 'sends stats to datadog' do
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)

      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end
  end

  # Captured from a live Passenger 6.1.8 instance running as a dynamic nginx
  # module on Amazon Linux 2023 (nginx 1.30.4 stable, rbenv Ruby 3.3.12). The
  # single app group runs as the `vagrant` user and the nginx.conf uses
  # `user root;` plus `passenger_default_user`, so the socket-path length trap
  # (PrivateTmp=true in the AL2023 nginx unit) had to be fixed before
  # passenger-status could run at all.
  context 'passenger 6 on nginx (Amazon Linux 2023)' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_6_status_nginx_al2023.xml'))
    end

    let(:passenger_status) do
      [['passenger.pool.used', '1'],
       ['passenger.pool.max', '6'],
       ['passenger.request_queue', '0'],

       ['passenger.capacity_used', '1'],
       ['passenger.get_wait_list_size', '0'],
       ['passenger.disable_wait_list_size', '0'],
       ['passenger.processes_being_spawned', '0'],
       ['passenger.enabled_process_count', '1'],
       ['passenger.disabling_process_count', '0'],
       ['passenger.disabled_process_count', '0'],

       ['passenger.processed', '1', { tags: ['passenger-process:0'] }],
       ['passenger.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.busyness', '0', { tags: ['passenger-process:0'] }],
       ['passenger.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.rss', '13716', { tags: ['passenger-process:0'] }],
       ['passenger.private_dirty', '2916', { tags: ['passenger-process:0'] }],
       ['passenger.pss', '6975', { tags: ['passenger-process:0'] }],
       ['passenger.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.real_memory', '2916', { tags: ['passenger-process:0'] }],
       ['passenger.vmsize', '831528', { tags: ['passenger-process:0'] }]]
    end

    it 'sends stats to datadog' do
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)

      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end
  end

  # Captured from a live Passenger 6.1.8 standalone instance started with
  # --min-instances 0 and never sent a request: the group exists, `<processes/>`
  # is empty, and every count is zero.
  context 'passenger 6 with no processes' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_6_status_no_processes.xml'))
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)
    end

    let(:passenger_status) do
      [['passenger.pool.used', '0'],
       ['passenger.pool.max', '4'],
       ['passenger.request_queue', '0'],

       ['passenger.capacity_used', '0'],
       ['passenger.get_wait_list_size', '0'],
       ['passenger.disable_wait_list_size', '0'],
       ['passenger.processes_being_spawned', '0'],
       ['passenger.enabled_process_count', '0'],
       ['passenger.disabling_process_count', '0'],
       ['passenger.disabled_process_count', '0']]
    end

    it 'sends the pool and group stats' do
      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end

    it 'sends no per-process stats' do
      allow(statsd).to receive(:gauge)

      expect(statsd).not_to receive(:gauge).with(anything, anything, hash_including(:tags))

      subject.run
    end
  end

  # Captured from a host running two Passenger instances, where passenger-status
  # refuses to guess and prints its instance list to stdout. Eleven lines of
  # non-XML: long enough to survive a fixed three-line header strip, which is how
  # this silently produced zero metrics rather than saying anything.
  context 'passenger 6 with multiple instances running' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_6_multiple_instances.txt'))
      allow(subject).to receive(:warn)
    end

    it 'sends nothing' do
      expect(Datadog::Statsd).not_to receive(:new)

      subject.run
    end

    it 'says why in the journal' do
      expect(subject).to receive(:warn).with(/no XML.*multiple Phusion Passenger/)

      subject.run
    end
  end

  context 'passenger 5 with multiple supergroups' do
    before do
      allow(subject).to receive(:`).and_return(File.read('spec/fixtures/passenger_5_status_multiple_supergroups.xml'))
    end

    let(:passenger_status) do
      [['passenger.pool.used', '2'],
       ['passenger.pool.max', '5'],
       ['passenger.request_queue', '999'],

       ['passenger.passenger_datadog_development.capacity_used', '2'],
       ['passenger.passenger_datadog_development.get_wait_list_size', '111'],
       ['passenger.passenger_datadog_development.disable_wait_list_size', '0'],
       ['passenger.passenger_datadog_development.processes_being_spawned', '0'],
       ['passenger.passenger_datadog_development.enabled_process_count', '2'],
       ['passenger.passenger_datadog_development.disabling_process_count', '0'],
       ['passenger.passenger_datadog_development.disabled_process_count', '0'],

       ['passenger.passenger_datadog_development.processed', '2', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.busyness', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.rss', '409596', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.private_dirty', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.pss', '267231', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.real_memory', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_development.vmsize', '812632', { tags: ['passenger-process:0'] }],

       ['passenger.passenger_datadog_development.processed', '3', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.sessions', '0', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.busyness', '0', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.concurrency', '1', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.cpu', '0', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.rss', '407972', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.private_dirty', '124832', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.pss', '265607', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.swap', '0', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.real_memory', '124832', { tags: ['passenger-process:1'] }],
       ['passenger.passenger_datadog_development.vmsize', '812536', { tags: ['passenger-process:1'] }],

       ['passenger.passenger_datadog_production.capacity_used', '2'],
       ['passenger.passenger_datadog_production.get_wait_list_size', '111'],
       ['passenger.passenger_datadog_production.disable_wait_list_size', '0'],
       ['passenger.passenger_datadog_production.processes_being_spawned', '0'],
       ['passenger.passenger_datadog_production.enabled_process_count', '2'],
       ['passenger.passenger_datadog_production.disabling_process_count', '0'],
       ['passenger.passenger_datadog_production.disabled_process_count', '0'],

       ['passenger.passenger_datadog_production.processed', '2', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.sessions', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.busyness', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.concurrency', '1', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.cpu', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.rss', '409596', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.private_dirty', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.pss', '267231', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.swap', '0', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.real_memory', '126456', { tags: ['passenger-process:0'] }],
       ['passenger.passenger_datadog_production.vmsize', '812632', { tags: ['passenger-process:0'] }]]
    end

    it 'sends stats to datadog' do
      allow(Datadog::Statsd).to receive(:new).and_return(statsd)
      allow(statsd).to receive(:close)

      passenger_status.each do |key, *value|
        expect(statsd).to receive(:gauge).with(key, *value)
      end

      subject.run
    end
  end
end
