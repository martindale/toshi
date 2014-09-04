module Toshi
  module Models
    class Output < Sequel::Model

      many_to_many :addresses

      def first_address
        address = addresses.first
        return nil unless address
        address.address
      end

      def spending_transactions
        tids = Input.where(prev_out: hsh, index: position).map(:hsh)
        Transaction.where(hsh: tids)
      end

      def spending_inputs
        Input.where(prev_out: hsh, index: position)
      end

      def transaction
        @transaction ||= Transaction.where(hsh: hsh).first
      end

      def btc
        ("%.8f" % (amount / 100000000.0)).to_f
      end

      def is_on_main_chain?
        return branch == Toshi::Models::Block::MAIN_BRANCH
      end

      def is_on_side_chain?
        return branch == Toshi::Models::Block::SIDE_BRANCH
      end

      def is_spendable?
        return false if spent
        is_on_main_chain?
      end

      def to_hash
        self.class.to_hash_collection([self]).first
      end

      def to_json
        to_hash.to_json
      end

      def self.to_hash_collection(outputs)
        output_hashes = []

        # this is a query
        max_height = Block.max_height

        # get confirmations
        confirmations_by_hash = {}
        tx_hashes = outputs.map{|output| output.hsh }
        Transaction.where(hsh: tx_hashes.uniq).each do |tx|
          confirmations_by_hash[tx.hsh] = max_height - tx.height
        end

        outputs.each do |output|
          parsed_script = Bitcoin::Script.new(output.script)
          o = {}
          o[:transaction_hash] = output.hsh
          o[:output_index] = output.position
          o[:amount] = output.amount
          o[:script] = parsed_script.to_string
          o[:script_hex] = output.script.unpack("H*")[0]
          o[:script_type] = parsed_script.type
          o[:addresses] = (parsed_script.get_addresses rescue ['unknown'])
          o[:spent] = output.spent
          o[:confirmations] = confirmations_by_hash[output.hsh]
          output_hashes << o
        end
        output_hashes
      end
    end
  end
end
