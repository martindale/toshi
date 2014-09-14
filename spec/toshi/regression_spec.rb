require 'spec_helper'
require 'open3'
require 'socket'
require 'timeout'

def is_port_open?(ip, port)
  Timeout.timeout(1) do
    begin
      s = TCPSocket.new(ip, port)
      s.close
      return true
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
      return false
    end
  end
rescue Timeout::Error
  return false
end

describe 'TheBlueMatt BitcoindComparisonTool', type: :regression do
  before(:all) do
    # setup regtest environment
    run_env = ENV.to_hash.merge(
      {'TOSHI_NETWORK' => 'regtest',
       'NODE_ACCEPT_INCOMING' => "true",
       'NODE_LISTEN_PORT' => '18444'})
    @pids = []
    cmd = "foreman start -c web=0,block_worker=1,transaction_worker=1,peer_manager=1"
    puts "Starting #{cmd}"
    logfile = "log/foreman.log"
    _, _, _, wait_thr = Open3.popen3(run_env, cmd + " 1>>#{logfile} 2>>#{logfile}" + " &")
    @pids << wait_thr.pid
    begin
      # wait until the peer manager is accepting connections (port 18444)
      Timeout::timeout(10) do
        until is_port_open?('127.0.0.1', "18444")
        end
      end
    rescue Timeout::Error
      raise "Could not connect to io_worker on port 18444 after 10 seconds"
    end
  end

  it "should complete successfully" do
    begin
      Timeout::timeout(240) do
        cmd = "java -Xms64m -Xmx512m -jar spec/regtest/test-scripts/BitcoindComparisonTool_jar/BitcoindComparisonTool.jar 1>>log/regtest.log 2>>log/regtest.log"
        _, _, _, regtest_thr = Open3.popen3(ENV, cmd)
        @pids << regtest_thr.pid
        expect(regtest_thr.value.exitstatus).to eq(0)
      end
    rescue Timeout::Error
      raise "regression test timeout"
    end
  end

  after(:all) do
    @pids.each do |pid|
      begin
        p "killing #{pid}"
        Process.kill 'TERM', pid
      rescue
      end
    end
    `ps aux | grep foreman | awk '{print $2}' | xargs kill`
  end
end
