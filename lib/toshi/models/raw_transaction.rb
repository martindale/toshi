module Toshi
  module Models
    class RawTransaction < Sequel::Model
      def bitcoin_tx; Bitcoin::P::Tx.new(payload); end
    end
  end
end
