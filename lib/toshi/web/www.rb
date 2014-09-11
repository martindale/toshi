require "toshi/web/base"

module Toshi
  module Web

    class WWW < Toshi::Web::Base
      get '/' do
        @network = Toshi.settings[:network]
        @available_peers = Toshi::Models::Peer.count
        @connected_peers = Toshi::Models::Peer.connected.count
        @database_size = Toshi::Utils.database_size
        @tx_count = Toshi::Models::Transaction.total_count
        @unconfirmed_tx_count = Toshi::Models::UnconfirmedTransaction.total_count
        @blocks_count = Toshi.db[:blocks].where(branch: 0).count()
        @side_blocks_count = Toshi.db[:blocks].where(branch: 1).count()
        @orphan_blocks_count = Toshi.db[:blocks].where(branch: 2).count()

        content_type 'text/html'
        erb :index
      end

      get '/websockets' do
        erb :websocket
      end
    end

  end
end
