require 'eventmachine'
require 'sinatra'
require "sinatra/namespace"

$client = RedisMQ::Channel.new(:client)
$client.init_heartbeat

module Toshi
  class Api < ::Sinatra::Base
    register Sinatra::Namespace
    class NotFoundError < StandardError; end
    class InvalidFormatError < StandardError; end

    set :root,            File.dirname(File.dirname(__FILE__))
    set :public_folder,   Proc.new { File.join(root, "toshi/web/static") }
    set :views,           Proc.new { File.join(root, "toshi/web/views") }

    helpers do
      def format
        fmt = params[:format].to_s
        fmt = 'json' if fmt == ''
        case fmt
        when 'hex' then content_type 'text/plain'
        when 'bin' then content_type 'application/octet-stream'
        when 'json' then content_type 'application/json'
        end
        fmt
      end
    end

    get '/stats.?:format?' do
      case format
      when 'json'
        {
          height: Toshi::Models::Block.max_height.to_s,
          peers: Toshi::Models::Peer.connected.count,
        }.to_json
      else
        raise InvalidFormatError
      end
    end

    # get collection of blocks
    get '/blocks.?:format?' do
      @blocks = Toshi::Models::Block.limit(50).order(Sequel.desc(:id))

      case format
      when 'json'
        @blocks.map(&:to_hash).to_json
      else
        raise InvalidFormatError
      end
    end

    # get latest block or search by hash or height
    get '/blocks/:hash.?:format?' do
      if params[:hash].to_s == 'latest'
        @block = Toshi::Models::Block.head
      elsif params[:hash].to_s.size < 64 && (Integer(params[:hash]) rescue false)
        @block = Toshi::Models::Block.where(height: params[:hash], branch: 0).first
      else
        @block = Toshi::Models::Block.where(hsh: params[:hash]).first
      end
      raise NotFoundError unless @block

      case format
      when 'json'
        @block.to_json
      when 'hex'
        @block.raw.payload.unpack("H*")[0]
      when 'bin'
        @block.raw.payload
      else
        raise InvalidFormatError
      end
    end

    # get block transactions
    get '/blocks/:hash/transactions.?:format?' do
      if params[:hash].to_s == 'latest'
        @block = Toshi::Models::Block.head
      elsif params[:hash].to_s.size < 64 && (Integer(params[:hash]) rescue false)
        @block = Toshi::Models::Block.where(height: params[:hash], branch: 0).first
      else
        @block = Toshi::Models::Block.where(hsh: params[:hash]).first
      end
      raise NotFoundError unless @block

      case format
      when 'json'
        @block.to_json(show_txs=true)
      else
        raise InvalidFormatError
      end
    end

    get '/transactions/:hash.?:format?' do
      @tx = (params[:hash].bytesize == 64 && Toshi::Models::Transaction.where(hsh: params[:hash]).first)
      @tx = (params[:hash].bytesize == 64 && Toshi::Models::UnconfirmedTransaction.where(hsh: params[:hash]).first) unless @tx
      raise NotFoundError unless @tx

      case format
      when 'json'
        @tx.to_json
      when 'hex'
        @tx.raw.payload.unpack("H*")[0]
      when 'bin'
        @tx.raw.payload
      else
        raise InvalidFormatError
      end
    end

    # submit new transaction to network
    post '/transactions.?:format?' do
      begin
        ptx = Bitcoin::P::Tx.new([params[:transaction]].pack("H*"))
      rescue
        return { error: 'malformed transaction' }.to_json
      end
      if Toshi::Models::RawTransaction.where(hsh: ptx.hash).first
        return { error: 'transaction already received' }.to_json
      end
      Toshi::Models::RawTransaction.create(hsh: ptx.hash, payload: Sequel.blob(ptx.payload))
      Toshi::Workers::TransactionWorker.perform_async ptx.hash, { 'sender' => nil }
      { success: true }.to_json
    end

    get '/addresses/:address.?:format?' do
      @address = Toshi::Models::Address.where(address: params[:address]).first
      raise NotFoundError unless @address

      case format
      when 'json'
        @address.to_json
      else
        raise InvalidFormatError
      end
    end

    get '/addresses/:address/transactions.?:format?' do
      @address = Toshi::Models::Address.where(address: params[:address]).first
      raise NotFoundError unless @address

      case format
      when 'json'
        @address.to_json options={show_txs:true, offset:params[:offset], limit:params[:limit]}
      else
        raise InvalidFormatError
      end
    end

    get '/addresses/:address/unspent_outputs.?:format?' do
      @address = Toshi::Models::Address.where(address: params[:address]).first
      raise NotFoundError unless @address

      case format
      when 'json'
        unspent_outputs = Toshi::Models::Output.to_hash_collection(@address.unspent_outputs)
        unspent_outputs.to_json
      else
        raise InvalidFormatError
      end
    end

    get '/unconfirmed_transactions' do
      mempool = Toshi::Models::UnconfirmedTransaction.mempool
      raise NotFoundError unless mempool

      case format
      when 'json'
        mempool = Toshi::Models::UnconfirmedTransaction.to_hash_collection(mempool)
        mempool.to_json
      else
        raise InvalidFormatError
      end
    end

    get '/toshi.?:format?' do
      hash = {
        peers: {
          available: Toshi::Models::Peer.count,
          connected: Toshi::Models::Peer.connected.count,
          info: Toshi::Models::Peer.connected.map{|peer| peer.to_hash}
        },
        database: {
          size: Toshi::Utils.database_size
        },
        transactions: {
          count: Toshi.db[:transactions].count(),
          unconfirmed_count: Toshi.db[:unconfirmed_transactions].count()
        },
        blocks: {
          main_count: Toshi::Models::Block.main_branch.count(),
          side_count: Toshi::Models::Block.side_branch.count(),
          orphan_count: Toshi::Models::Block.orphan_branch.count(),
        },
        status: Toshi::Utils.status
      }

      case format
      when 'json'
        hash.to_json
      else
        raise InvalidFormatError
      end
    end
  end
end
