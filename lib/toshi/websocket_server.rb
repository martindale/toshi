require 'faye/websocket'

module Toshi

  class WebSocketMiddleware
    attr_accessor :mq_client, :connections
    attr_reader :chan

    def ensure_reactor_running
      @reactor = Thread.new { EM.run } unless EM.reactor_running?
    end

    def initialize(app)
      ensure_reactor_running
      @app = app

      @connections = []
      @chan = { blocks: EM::Channel.new, transactions: EM::Channel.new }

      # client channel listening for processor messages
      @mq_client = RedisMQ::Channel.new(:client){|sender, job|
        case job['msg']
        when 'new_block'
          @chan[:blocks].push(job)
        when 'new_transaction'
          @chan[:transactions].push(job)
        end
      }

      @mq_client.init_heartbeat
      @mq_client.init_poll
    end

    def handle_websocket(env)
      connection = Toshi::WebSocketConnection.new(env, self)
      connection.socket.rack_response
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        handle_websocket(env)
      else
        @app.call(env)
      end
    end
  end

  class WebSocketConnection
    attr_reader :socket

    def initialize(env, connection_manager)
      @channel_subscriptions = {}

      @socket = Faye::WebSocket.new(env)
      @socket.onmessage = method(:on_message)
      @socket.onclose   = method(:on_close)
      #p [:open, @socket.url, @socket.version, @socket.protocol]

      @connection_manager = connection_manager
      @connection_manager.connections << self
    end

    def on_close(event)
      #p [:close, event.code, event.reason]
      @connection_manager.chan.keys.each{|channel_name| unsubscribe_channel(channel_name) }
      @connection_manager.connections.delete(self)
      @socket = nil
    end

    def on_message(event)
      begin
        cmd = JSON.parse(event.data)
        raise "parse error" if cmd.nil?
      rescue Exception => e
        #p [:message, event]
        @socket.send({ message_received: event.data }.to_json)
        return nil
      end

      if cmd.key?('subscribe')
        case cmd['subscribe']
          when 'blocks'
            subscribe_channel(:blocks, :on_channel_send_block)
          when 'transactions'
            subscribe_channel(:transactions, :on_channel_send_transaction)
        end
      end

      if cmd.key?('unsubscribe')
        case cmd['unsubscribe']
          when 'blocks'
            unsubscribe_channel(:blocks)
          when 'transactions'
            unsubscribe_channel(:transactions)
        end
      end

      if cmd.key?('fetch')
        case cmd['fetch']
          when 'latest_block'
            on_fetch_latest_block()
          when 'latest_transaction'
            on_fetch_latest_transaction
        end
      end

    end

    def write_socket(data)
      @socket.send(data) if @socket
    end

    # send a block to a connected websocket
    def on_channel_send_block(msg)
      block = Toshi::Models::Block.where(hsh: msg['hash']).first
      return unless block
      write_socket({ subscription: 'blocks', data: block.to_hash }.to_json)
    end

    # send a transaction to a connected websocket
    def on_channel_send_transaction(msg)
      tx = Toshi::Models::UnconfirmedTransaction.from_hsh(msg['hash']).first
      return unless tx
      write_socket({ subscription: 'transactions', data: tx.to_hash }.to_json)
    end

    def on_fetch_latest_block
      block = Toshi::Models::Block.head
      return unless block
      write_socket({ fetched: 'latest_block', data: block.to_hash }.to_json)
    end

    def on_fetch_latest_transaction
      tx = Toshi::Models::UnconfirmedTransaction.first
      return unless tx
      write_socket({ fetched: 'latest_transaction', data: tx.to_hash }.to_json)
    end

    def subscribe_channel(channel_name, method_name)
      @channel_subscriptions[channel_name] ||= @connection_manager.chan[channel_name].subscribe(&method(method_name))
    end

    def unsubscribe_channel(channel_name)
      if @channel_subscriptions[channel_name]
        @connection_manager.chan[channel_name].unsubscribe(@channel_subscriptions[channel_name])
        @channel_subscriptions[channel_name] = nil
      end
    end
  end

end
