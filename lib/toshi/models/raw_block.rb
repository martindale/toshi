module Toshi
  module Models
    class RawBlock < Sequel::Model

      def bitcoin_block
        Bitcoin::P::Block.new(payload)
      end
    end
  end
end
