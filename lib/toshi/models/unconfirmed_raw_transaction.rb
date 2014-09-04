module Toshi
  module Models
    class UnconfirmedRawTransaction < Sequel::Model
      def bitcoin_tx; Bitcoin::P::Tx.new(payload); end
    end
  end
end
