require 'eventmachine'

module Toshi
  class ConnectionHandler < EM::Connection
    LATENCY_MAX = (5*60*1000) # 5min in ms
    MAX_BLOCKS_IN_TRANSIT_PER_PEER = 128 # from main.h

    attr_reader :host, :port, :version, :direction, :state, :latency_ms, :peer

    def uptime
      @started ? (Time.now - @started).to_i : 0
    end

    def initialize(node, host, port, direction, peer, io_worker)
      @node, @host, @port, @direction = node, host, port, direction
      @parser = ::Bitcoin::Protocol::Parser.new(self)
      @state = :new
      @version, @started = nil, nil
      @port, @host = *Socket.unpack_sockaddr_in(get_peername)  if get_peername
      @ping_nonce, @latency_ms = nil, nil
      @debug = true
      @blocks_to_download = []
      @blocks_in_flight = []

      @peer = peer
      @io_worker = io_worker
    end

    def post_init
      @peer = Toshi::Models::Peer.get(@host)
      begin_handshake
    end

    def log(msg)
      @debug ||= Toshi.settings[:debug]
      puts "#{@host}:#{@port}: " + msg if @debug
    end

    def receive_data(data)
      @parser.parse(data)
    end

    def unbind
      log "Disconnected"
      @state = :disconnected
      @peer.update({connected: false}) if @peer
      @io_worker.connections.delete(self)
    end

    def begin_handshake
      @state = :handshake
      send_version if outgoing?
    end

    def complete_handshake
      return unless @state == :handshake
      log 'Handshake completed'
      @state, @started = :connected, Time.now
      @peer.update({worker_name: @io_worker.id, connected: true}) if @peer
      @io_worker.connections << self
      EM.add_timer(2){ send_getblocks }
    end

    def on_version(version)
      log ">> version: #{version.version}, user_agent: #{version.user_agent}" if @debug
      @version = version
      send_version if incoming?
      send_data(Bitcoin::Protocol.verack_pkt) if incoming?
      complete_handshake if outgoing?
    end

    def on_verack
      log '<< on_verack' if @debug
      complete_handshake if incoming?
    end

    def send_getblocks(locator = Toshi::Models::Block.getblocks_locator)
      if @debug
        log "<< getblocks: ["
        locator.each_with_index{|hsh,idx|
          block = Toshi::Models::Block.where(hsh: hsh).first
          log " #{idx}: #{hsh}, branch: #{block.branch_name}, height: #{block.height}" if block
        }
        log "]"
      else
        log "<< getblocks: #{locator.first}"
      end

      pkt = Bitcoin::Protocol.getblocks_pkt(@version.version, locator)
      send_data(pkt)
    end

    def on_headers(headers)
      log ">> headers #{headers}"
    end

    def on_getheaders(v, hashes, stophash)
      log ">> getheaders #{v}, #{hashes}, #{stophash}"
      # if none of the hashes are in our main branch, start from the genesis
      # block
      b = Toshi::Models::Block.main_branch.where(prev_block: hashes).order(:height).last ||
        Toshi::Models::Block.where(hsh: Bitcoin.network[:genesis_hash]).first
      blocks = []
      while blocks.size < 2000 && b && b.hsh != stophash
        blocks << Toshi::Models::RawBlock.where(hsh: b.hsh).first.bitcoin_block
        b = Toshi::Models::Block.main_branch.where(prev_block: b.hsh).first
      end
      pkt = Bitcoin::Protocol.headers_pkt(@version.version, blocks)
      log "<< headers #{blocks.size} blocks sent"
      send_data(pkt)
    end

    def on_inv_transaction(hash)
      # already processed it.
      return if Toshi::Models::Transaction.where(hsh: hash.hth).any?
      return if Toshi::Models::UnconfirmedTransaction.where(hsh: hash.hth).any?

      if Toshi::Models::UnconfirmedRawTransaction.where(hsh: hash.hth).any?
        # already have it downloaded but not imported, try again.
        Toshi::Workers::TransactionWorker.perform_async hash.hth, { 'sender' => connection_info }
        return
      end

      send_getdata_tx(hash)
    end

    def send_getdata_tx(hash)
      send_data( Bitcoin::Protocol.getdata_pkt(:tx, [hash]) )
    end

    def on_inv_block(hash)
      log ">> inv block: #{hash.hth}"
      if block = Toshi::Models::Block.where(hsh: hash.hth).first
        log "already have block" if @debug
        if block.is_orphan_chain?
          if block.previous && !block.previous.is_orphan_chain?
            if Toshi::Models::RawBlock.where(hsh: hash.hth).any?
              # reprocess block since it may now connect to a main or side chain
              log "reprocessing block as it now has a non-orphan parent" if @debug
              Toshi::Workers::BlockWorker.perform_async block.hsh, { 'sender' => connection_info }
            else
              # we should have all RawBlocks but past bugs may have made this not true.
              add_block_to_download_queue(hash)
            end
          end
          # bitcoind sends another 'getblocks' if it gets an inv for an existing orphan.
          log "block is on orphan chain, sending getblocks" if @debug
          send_getblocks
        end
        # already processed it.
        return
      end

      add_block_to_download_queue(hash)
    end

    def add_block_to_download_queue(hash)
      @blocks_to_download << hash
      return if @blocks_in_flight.count >= MAX_BLOCKS_IN_TRANSIT_PER_PEER
      @blocks_in_flight << @blocks_to_download.shift
      send_getdata_block(@blocks_in_flight.last)
    end

    def on_block_processed(hsh)
      @blocks_in_flight.shift
      log "blocks to download: #{@blocks_to_download.count}, in-flight: #{@blocks_in_flight.count}" if @debug
      return if @blocks_to_download.empty?
      @blocks_in_flight << @blocks_to_download.shift
      send_getdata_block(@blocks_in_flight.last)
    end

    def send_getdata_block(hash)
      send_data( Bitcoin::Protocol.getdata_pkt(:block, [hash]))
    end

    def on_get_transaction(hash)
      log ">> get transaction: #{hash.hth}"
      if tx = Toshi::Models::RawTransaction.where(hsh: hash.hth).first
        send_data( Bitcoin::Protocol.pkt("tx", tx.payload) )
      end
    end

    def on_get_block(hash)
      log ">> get block: #{hash.hth}"
      if block = Toshi::Models::RawBlock.where(hsh: hash.hth).first
        send_data( Bitcoin::Protocol.pkt("block", block.payload) )
      end
    end

    def on_addr(addr)
      log ">> addr: #{addr.ip}:#{addr.port} alive: #{addr.alive?}, service: #{addr.service}"
    end

    def connection_info
      { 'type' => @io_worker.type, 'id' => @io_worker.id, 'peer' => "#{@host}:#{@port}" }
    end

    def on_tx(tx)
      log ">> tx: #{tx.hash} (#{tx.payload.size} bytes)"
      unless Toshi::Models::UnconfirmedRawTransaction.where(hsh: tx.hash).any?
        Toshi::Models::UnconfirmedRawTransaction.create(hsh: tx.hash, payload: Sequel.blob((tx.payload || tx.to_payload)))
        Toshi::Workers::TransactionWorker.perform_async tx.hash, { 'sender' => connection_info }
      end
    end

    def on_block(blk)
      log ">> block: #{blk.hash} (#{blk.payload.size} bytes)"
      unless !Toshi::Models::RawBlock.where(hsh: blk.hash).empty?
        Toshi::Models::RawBlock.create(hsh: blk.hash, payload: Sequel.blob((blk.payload || blk.to_payload)))
      end

      # send it to the sidekiq worker for processing.
      # if it processes this as an orphan it will tell us to get more blocks.
      Toshi::Workers::BlockWorker.perform_async blk.hash, { 'sender' => connection_info }
    end

    # received +alert+ message for given +alert+.
    # TODO: implement alert logic, store, display, relay
    def on_alert(alert)
      log ">> alert: #{alert.inspect}"
    end

    # received +getblocks+ message.
    # TODO: locator fallback
    def on_getblocks(version, hashes, stop_hash)
      log ">> getblocks: #{version}, #{hashes.size}, #{stop_hash}"
    end

    # received +getaddr+ message.
    # send +addr+ message with peer addresses back.
    def on_getaddr
      #addrs = @node.addrs.select{|a| a.time > Time.now.to_i - 10800 }.shuffle[0..250]
      #p "<< addr (#{addrs.size})"
      #send_data P::Addr.pkt(*addrs)
    end

    # begin handshake; send +version+ message
    def send_version
      version = Bitcoin::Protocol::Version.new({
        :version    => 70001,
        :last_block => Toshi::Models::Block.max_height,
        :from       => "127.0.0.1:#{Bitcoin.network[:default_port]}",
        :to         => @host,
        :user_agent => user_agent,
      })
      send_data(version.to_pkt)
      log ">> version: #{version.version}, user_agent: #{version.user_agent}" if @debug
    end

    def user_agent
      "/Toshi:#{Toshi::VERSION}"
    end

    def peer_addr
      "#{host}:#{port}"
    end

    # received +ping+ message with given +nonce+.
    # send +pong+ message back, if +nonce+ is set.
    # network versions <=60000 don't set the nonce and don't expect a pong.
    def on_ping nonce
      log ">> ping (#{nonce})"
      send_data(Bitcoin::Protocol.pong_pkt(nonce)) if nonce
    end

    def send_inv type, hashes
      hashes.each_slice(251) do |slice|
        pkt = Bitcoin::Protocol.inv_pkt(type, slice.map(&:htb))
        log "<< inv #{type}: #{slice[0][0..16]}" + (slice.size > 1 ? "..#{slice[-1][0..16]}" : "")
        send_data(pkt)
      end
    end

    def on_mempool
      log ">> mempool" if @debug
      inv = Toshi::Models::UnconfirmedTransaction.mempool.select_map(:hsh)
      send_inv(:tx, inv) if inv.any?
    end

    def incoming?
      @direction == :in
    end

    def outgoing?
      @direction == :out
    end
  end
end
