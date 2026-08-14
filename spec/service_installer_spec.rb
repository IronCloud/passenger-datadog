# frozen_string_literal: true

require 'spec_helper'
require 'service_installer'
require 'tmpdir'

describe ServiceInstaller do
  let(:bin_dir) { Dir.mktmpdir }
  let(:unit_dir) { Dir.mktmpdir }
  let(:passenger_status) { File.join(bin_dir, 'passenger-status') }
  let(:env) { { 'PATH' => bin_dir } }

  subject do
    described_class.new(unit_dir: unit_dir, executable: '/opt/gems/bin/passenger-datadog',
                        search_paths: [bin_dir], env: env)
  end

  before do
    File.write(passenger_status, '')
    File.chmod(0o755, passenger_status)
  end

  after do
    FileUtils.remove_entry(bin_dir)
    FileUtils.remove_entry(unit_dir)
  end

  describe '#unit' do
    it 'invokes the running ruby by absolute path' do
      expect(subject.unit).to include("ExecStart=#{RbConfig.ruby} /opt/gems/bin/passenger-datadog")
    end

    it 'puts the passenger-status directory on the service PATH' do
      expect(subject.unit).to include("Environment=PATH=#{bin_dir}:")
    end

    it 'keeps the systemd default directories on the service PATH' do
      expect(subject.unit).to include('/usr/local/bin').and include('/usr/bin')
    end

    it 'references an optional environment file for the Datadog settings' do
      expect(subject.unit).to include('EnvironmentFile=-/etc/default/passenger-datadog')
    end

    it 'defaults to running as root' do
      expect(subject.unit).to include('User=root').and include('Group=root')
    end

    it 'honors a custom user and group' do
      installer = described_class.new(user: 'app', group: 'web', unit_dir: unit_dir,
                                      search_paths: [bin_dir], env: env)

      expect(installer.unit).to include('User=app').and include('Group=web')
    end
  end

  describe '#passenger_status' do
    it 'raises a helpful error when passenger-status cannot be found' do
      installer = described_class.new(unit_dir: unit_dir, search_paths: ['/nonexistent'], env: {})

      expect { installer.unit }.to raise_error(ServiceInstaller::Error, /passenger-status not found/)
    end

    it 'honors an explicitly provided path' do
      installer = described_class.new(unit_dir: unit_dir, passenger_status: '/opt/pass/bin/passenger-status',
                                      search_paths: ['/nonexistent'], env: {})

      expect(installer.unit).to include('Environment=PATH=/opt/pass/bin:')
    end

    # Under sudo, secure_path strips rvm/rbenv directories, so PATH alone is not
    # enough to find the binary that ships beside this executable.
    it 'looks beside the executable before consulting PATH' do
      installer = described_class.new(unit_dir: unit_dir, executable: File.join(bin_dir, 'passenger-datadog'),
                                      env: { 'PATH' => '/nonexistent' })

      expect(installer.passenger_status).to eq(passenger_status)
    end
  end

  describe '#install' do
    context 'not running as root' do
      before { allow(Process).to receive(:uid).and_return(1000) }

      it 'refuses to write the unit' do
        expect { subject.install }.to raise_error(ServiceInstaller::Error, /must run as root/)
      end
    end

    context 'running as root' do
      before do
        allow(Process).to receive(:uid).and_return(0)
        allow(subject).to receive(:system).with('systemctl', 'daemon-reload').and_return(true)
      end

      it 'writes the unit and returns its path' do
        expect(subject.install).to eq(File.join(unit_dir, 'passenger-datadog.service'))
        expect(File.read(subject.unit_path)).to include('Description=Send Passenger stats to Datadog')
      end

      it 'writes the unit world-readable' do
        subject.install

        expect(File.stat(subject.unit_path).mode & 0o777).to eq(0o644)
      end

      it 'refuses to clobber an existing unit' do
        subject.install

        expect { subject.install }.to raise_error(ServiceInstaller::Error, /already exists/)
      end

      it 'overwrites an existing unit when forced' do
        subject.install

        expect { subject.install(force: true) }.not_to raise_error
      end

      it 'raises when daemon-reload fails' do
        allow(subject).to receive(:system).with('systemctl', 'daemon-reload').and_return(false)

        expect { subject.install }.to raise_error(ServiceInstaller::Error, /daemon-reload failed/)
      end
    end
  end

  describe '#uninstall' do
    before do
      allow(Process).to receive(:uid).and_return(0)
      allow(subject).to receive(:system).and_return(true)
    end

    it 'returns nil when no unit is installed' do
      expect(subject.uninstall).to be_nil
    end

    it 'removes an installed unit' do
      subject.install

      expect(subject.uninstall).to eq(subject.unit_path)
      expect(File.exist?(subject.unit_path)).to be(false)
    end
  end
end
