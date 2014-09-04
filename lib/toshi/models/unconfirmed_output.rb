module Toshi
  module Models
    class UnconfirmedOutput < Sequel::Model

      many_to_many :unconfirmed_addresses,
                   :left_key => :output_id,
                   :right_key => :address_id,
                   :join_table => :unconfirmed_addresses_outputs

      def transaction
        @transaction ||= UnconfirmedTransaction.where(hsh: hsh).first
      end

      def self.prevout(txin)
        UnconfirmedOutput.where(hsh: txin.previous_output, position: txin.prev_out_index).first
      end

      def btc
        ("%.8f" % (amount / 100000000.0)).to_f
      end
    end
  end
end
