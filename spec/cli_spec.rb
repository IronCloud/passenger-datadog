# frozen_string_literal: true

require 'spec_helper'
require 'service_installer'
require 'open3'
require 'socket'
require 'tmpdir'

# The executable is exercised as a subprocess: its argument parsing, dispatch,
# and sd_notify handshake only fail once the file is actually run, which is how
# the Type=notify defect fixed during the 2.0.0 cycle stayed hidden.
describe 'bin/passenger-datadog' do
  let(:bin) { File.expand_path('../bin/passenger-datadog', __dir__) }

  def run(*args, env: {})
    Open3.capture3(env, RbConfig.ruby, bin, *args)
  end

  describe 'usage' do
    it 'prints usage for --help' do
      _out, err, status = run('--help')

      expect(err).to include('Usage: passenger-datadog [command] [options]')
      expect(status.exitstatus).to eq(1)
    end

    # A leading dash must not be mistaken for a command name.
    it 'treats a leading option as an option, not a command' do
      _out, err, _status = run('--help')

      expect(err).not_to include('unknown command')
    end

    it 'rejects an unknown command' do
      _out, err, status = run('bogus')

      expect(err).to include('unknown command: bogus')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe 'install-service --dry-run' do
    def dry_run(*args)
      out, _err, status = run('install-service', '--dry-run',
                              '--passenger-status', '/opt/pass/bin/passenger-status', *args)
      expect(status.exitstatus).to eq(0)
      out
    end

    it 'prints the whole unit' do
      expect(dry_run).to include('Description=Send Passenger stats to Datadog')
        .and include('[Install]')
    end

    it 'invokes the running ruby by absolute path' do
      expect(dry_run).to include("ExecStart=#{RbConfig.ruby} #{bin}")
    end

    it 'passes the requested user and group through' do
      expect(dry_run('--user', 'app', '--group', 'web')).to include('User=app').and include('Group=web')
    end

    it 'honors the explicit passenger-status path' do
      expect(dry_run).to include('Environment=PATH=/opt/pass/bin:')
    end

    it 'bakes in the gem environment systemd does not inherit' do
      expect(dry_run).to include("Environment=GEM_HOME=#{Gem.dir}")
    end
  end

  describe 'install-service' do
    it 'reports the root requirement as a message, not a backtrace' do
      skip 'spec suite is running as root' if Process.uid.zero?

      _out, err, status = run('install-service', '--passenger-status', '/opt/pass/bin/passenger-status')

      expect(err).to include('passenger-datadog: must run as root')
      expect(err).not_to include('service_installer.rb:')
      expect(status.exitstatus).to eq(1)
    end
  end

  # systemd's $NOTIFY_SOCKET is SOCK_DGRAM; connecting a stream socket to it
  # gets EPROTOTYPE, which made Type=notify time out into a restart loop.
  describe 'sd_notify' do
    let(:dir) { Dir.mktmpdir }
    let(:server) { Socket.new(:UNIX, :DGRAM) }

    before do
      # Shadow passenger-status with a silent stub so the collection loop does
      # not depend on a live Passenger: it warns about the empty output and
      # sleeps, which is all these examples need it to do.
      stub = File.join(dir, 'passenger-status')
      File.write(stub, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, stub)
    end

    after do
      server.close
      FileUtils.remove_entry(dir)
    end

    def collect_with(notify_socket)
      pid = Process.spawn({ 'NOTIFY_SOCKET' => notify_socket, 'PATH' => "#{dir}:#{ENV.fetch('PATH', '')}" },
                          RbConfig.ruby, bin, out: File::NULL, err: File::NULL)
      yield pid
    ensure
      reap(pid)
    end

    # Ruby defers a trapped signal until a blocking backtick returns, and
    # bundler puts the gem bin directory ahead of the stub on PATH, so on a
    # machine with a real passenger-status the child can sit in that call for a
    # while. Escalate rather than let the suite hang.
    def reap(pid)
      Process.kill('TERM', pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      until Process.waitpid(pid, Process::WNOHANG)
        next sleep(0.05) if Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

        Process.kill('KILL', pid)
        return Process.waitpid(pid)
      end
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def expect_ready
      raise 'no readiness notification arrived within 15s' unless server.wait_readable(15)

      expect(server.recvfrom(64).first).to eq('READY=1')
    end

    it 'notifies readiness over a filesystem socket' do
      path = File.join(dir, 'notify')
      server.bind(Socket.pack_sockaddr_un(path))

      collect_with(path) { expect_ready }
    end

    it 'notifies readiness over an abstract-namespace socket' do
      name = "passenger-datadog-spec-#{Process.pid}"
      server.bind(Socket.pack_sockaddr_un("\0#{name}"))

      collect_with("@#{name}") { expect_ready }
    end

    it 'keeps running when the notify socket does not exist' do
      collect_with(File.join(dir, 'missing')) do |pid|
        sleep(1)

        expect(Process.waitpid(pid, Process::WNOHANG)).to be_nil
      end
    end
  end
end
