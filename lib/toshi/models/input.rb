module Toshi
  module Models
    class Input < Sequel::Model

      def first_address
        @previous_output ||= Output.where(hsh: prev_out, position: index).first
        address = @previous_output.addresses.first
        return nil unless address
        address.address
      end

      def previous_output
        @previous_output ||= Output.where(hsh: prev_out, position: index).first
      end

      def previous_transaction
        @previous_transaction ||= Transaction.where(hsh: prev_out).first
      end

      def transaction
        @transaction ||= Transaction.where(hsh: hsh).first
      end

      def transaction_pool
        @transaction_pool ||= Transaction.where(hsh: hsh).first.pool
      end

      def coinbase?
        prev_out == INPUT_COINBASE_HASH && index == 0xffffffff
      end

      def in_view?(include_memory_pool=true)
        transaction.in_view?(include_memory_pool)
      end

      INPUT_COINBASE_HASH = "00"*32
    end
  end
end
