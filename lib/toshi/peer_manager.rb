require "eventmachine"

module Toshi
  # PeerManager is responsible for managing connections to peers and sending
  # the processor work via the message queue.
  class PeerManager
    include Logging

    attr_accessor :mq_client, :connections

    def initialize(peers)
      @connections = []
      @peers = peers

      logger.info{ "Initialzed peer manager with peer list: #{peers}" }

      # listening for processor messages
      @mq_client = RedisMQ::Channel.new(:worker){|sender,job|
        p [:worker, job]

        case job['msg']
        when 'bootstrap'
          Toshi::Models::Peer.bootstrap(job['dns'])
        when 'get_blocks'
          conn = get_conn_by_addr(job['peer'])
          conn.send_getblocks if conn
        when 'block_processed'
          conn = get_conn_by_addr(job['peer'])
          conn.on_block_processed(job['block_hash']) if conn
        when 'relay_tx'
          @connections.each{|conn| conn.send_inv(:tx, [job['hash']]) }
        when 'relay_block'
          max_height = Toshi::Models::Block.max_height
          @connections.each{|conn|
            start_height = conn.version.last_block
            # see the bottom of ActivateBestChain() in main.cpp
            if max_height > start_height - 2000
              conn.send_inv(:block, [job['hash']])
            end
          }
        else
          sender.reply(job, 'msg' => 'pong')
        end
      }

      @mq_client.init_heartbeat
      @mq_client.init_poll
    end

    # identified by our mq client
    def id
      @mq_client.id
    end

    # what type of client are we?
    def type
      @mq_client.key
    end

    # retrieve a connection given an address of form "IP:port"
    def get_conn_by_addr addr
      @connections.find{|conn| conn.peer_addr == addr }
    end

    def clear_peers
      # set them all to disconnected in the db
      Toshi::Models::Peer.all.each{|peer|
        peer.update({connected: false, worker_name: ''})
      }
    end

    def check_peers
      Toshi::Models::Peer.where([[:ip, @peers]]).each{|peer|
        # reconnect
        add_peer(peer.ip) if !peer.connected
      }
      if Toshi::Models::Peer.connected.count < Toshi.settings[:max_peers]
        peers = Toshi::Models::Peer.bootstrap()
        if peers && peer = peers.sample
          logger.info { "Bootstrapping peer #{peer.ip}:#{peer.port}" }
          peer.connect!(self)
        end
      end
    end

    def add_peer(ip)
      peer = Toshi::Models::Peer.get(ip)
      peer.connect!(self) if peer
    end

    # main event loop
    def run
      logger.info { "Starting peer manager: #{@mq_client.to_s}" }
      clear_peers
      EM.run{
        EM.add_periodic_timer(1){ RedisMQ::Channel.flush! }
        EM.add_periodic_timer(5) { check_peers }
        EM.add_timer(2){ @peers.each{|ip| add_peer(ip) } }
        @mq_client
        if ENV['NODE_ACCEPT_INCOMING']
          host, port = "0.0.0.0", ENV['NODE_LISTEN_PORT'] || Bitcoin.network[:default_port]
          logger.info{ "Attempting to accept connections on address #{host}, port #{port}..." }
          EventMachine.start_server host, port, Toshi::ConnectionHandler, nil, host, port, :in, nil, self
          logger.info{ "Now accepting connections on address #{host}, port #{port}..." }
        end
      }
    end
  end
end
