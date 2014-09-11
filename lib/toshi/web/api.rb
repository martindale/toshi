require "toshi/web/base"

unless $client
  $client = RedisMQ::Channel.new(:client)
  $client.init_heartbeat
end

module Toshi
  module Web

    class Api < Toshi::Web::Base
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

        def json(obj)
          options = {:space => ''}
          JSON.pretty_generate(obj, options)
        end
      end

      ####
      ## /blocks
      ####

      # get collection of blocks
      get '/blocks.?:format?' do
        @blocks = Toshi::Models::Block.limit(50).order(Sequel.desc(:id))

        case format
        when 'json'
          json @blocks.map(&:to_hash)
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
        when 'json'; json(@block.to_hash)
        when 'hex';  @block.raw.payload.unpack("H*")[0]
        when 'bin';  @block.raw.payload
        else raise InvalidFormatError
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
          json(@block.to_hash(show_txs=true))
        else
          raise InvalidFormatError
        end
      end

      ####
      ## /transactions
      ####

      # submit new transaction to network
      put '/transactions.?:format?' do
        begin
          ptx = Bitcoin::P::Tx.new([params[:hex]].pack("H*"))
        rescue
          return { error: 'malformed transaction' }.to_json
        end
        if Toshi::Models::RawTransaction.where(hsh: ptx.hash).first
          return { error: 'transaction already received' }.to_json
        end
        Toshi::Models::RawTransaction.create(hsh: ptx.hash, payload: Sequel.blob(ptx.payload))
        Toshi::Workers::TransactionWorker.perform_async ptx.hash, { 'sender' => nil }
        { hash: ptx.hash }.to_json
      end

      get '/transactions/:hash.?:format?' do
        @tx = (params[:hash].bytesize == 64 && Toshi::Models::Transaction.where(hsh: params[:hash]).first)
        @tx ||= (params[:hash].bytesize == 64 && Toshi::Models::UnconfirmedTransaction.where(hsh: params[:hash]).first)
        raise NotFoundError unless @tx

        case format
        when 'json'; json(@tx.to_hash)
        when 'hex';  @tx.raw.payload.unpack("H*")[0]
        when 'bin';  @tx.raw.payload
        else raise InvalidFormatError
        end
      end

      get '/transactions/unconfirmed' do
        mempool = Toshi::Models::UnconfirmedTransaction.mempool
        raise NotFoundError unless mempool

        case format
        when 'json'
          mempool = Toshi::Models::UnconfirmedTransaction.to_hash_collection(mempool)
          json(mempool)
        else
          raise InvalidFormatError
        end
      end

      ####
      ## /addresses
      ####

      get '/addresses/:address.?:format?' do
        address = Toshi::Models::Address.where(address: params[:address]).first
        raise NotFoundError unless address

        case format
        when 'json';
          json(address.to_hash)
        else
          raise InvalidFormatError
        end
      end

      get '/addresses/:address/transactions.?:format?' do
        address = Toshi::Models::Address.where(address: params[:address]).first
        raise NotFoundError unless address

        case format
        when 'json'
          json address.to_hash(options={show_txs:true, offset:params[:offset], limit:params[:limit]})
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
          json(unspent_outputs)
        else
          raise InvalidFormatError
        end
      end

      ####
      ## /toshi
      ####

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
            count: Toshi::Models::Transaction.total_count,
            unconfirmed_count: Toshi::Models::UnconfirmedTransaction.total_count
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
          json(hash)
        else
          raise InvalidFormatError
        end
      end
    end

  end
end
