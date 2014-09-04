module Toshi
  module Models
    class UnconfirmedInput < Sequel::Model

      def transaction
        @transaction ||= UnconfirmedTransaction.where(hsh: hsh).first
      end

      def coinbase?
        prev_out == INPUT_COINBASE_HASH && index == 0xffffffff
      end

      def self.from_txin(txin)
        UnconfirmedInput.where(prev_out: txin.previous_output, index: txin.prev_out_index)
      end

      INPUT_COINBASE_HASH = "00"*32
    end
  end
end
