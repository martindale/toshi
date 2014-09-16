module Toshi
  module Models
    class Address < Sequel::Model

      many_to_many :outputs

      def unspent_outputs
        Output.join(:unspent_outputs, :output_id => :id).where(address_id: id)
      end

      def spent_outputs
        outputs_dataset.where(spent: true, branch: Block::MAIN_BRANCH)
      end

      def balance
        total_received - total_sent
      end

      def utxo_balance
        # if this isn't the same as the cached balance it's a problem.
        Toshi.db[:unspent_outputs].where(address_id: id).sum(:amount).to_i || 0
      end

      # t = epoch time
      def balance_at(t=nil)
        t = Time.now.to_i if !t || t == 0
        # first we need to find the block height
        block = Block.order(Sequel.desc(:time)).where(time: 0..t).first
        return 0 unless block
        # sum the ledger entries for this address on the main branch up to this height
        Toshi.db[:address_ledger_entries].where(address_id: id).join(:transactions, :id => :transaction_id)
          .where(pool: Transaction::TIP_POOL).where("height <= #{block.height}").sum(:amount).to_i || 0
      end

      def transactions(offset=0, limit=100)
        tids = Toshi.db[:address_ledger_entries].where(address_id: id)
                           .select(:transaction_id).group_by(:transaction_id)
                           .order(Sequel.desc(:transaction_id)).offset(offset).limit(limit).map(:transaction_id)
        return [] unless tids.any?
        Transaction.where(id: tids).order(Sequel.desc(:id))
      end

      def btc
        ("%.8f" % (balance / 100000000.0)).to_f
      end

      HASH160_TYPE = 0
      P2SH_TYPE    = 1

      def type
        case address_type
        when HASH160_TYPE; :hash160
        when P2SH_TYPE;    :p2sh
        end
      end

      def to_hash(options={})
        self.class.to_hash_collection([self], options).first
      end

      def self.to_hash_collection(addresses, options={})
        Toshi::Utils.sanitize_options(options)

        collection = []

        addresses.each{|address|
          hash = {}
          hash[:hash] = address.address
          hash[:balance] = address.balance
          hash[:received] = address.total_received
          hash[:sent] = address.total_sent

          amount_unconfirmed_spent = 0
          if unconfirmed_address = Toshi::Models::UnconfirmedAddress.where(address: address.address).first
            amount_unconfirmed_spent = unconfirmed_address.amount_confirmed_spent_by_unconfirmed(address)
          end

          hash[:unconfirmed_received] = unconfirmed_address ? unconfirmed_address.outputs.sum(:amount).to_i : 0
          hash[:unconfirmed_sent] = unconfirmed_address ? unconfirmed_address.spent_outputs.sum(:amount).to_i : 0
          hash[:unconfirmed_sent] += amount_unconfirmed_spent
          hash[:unconfirmed_balance] = unconfirmed_address ? unconfirmed_address.balance : address.balance

          if options[:show_txs]
            if unconfirmed_address
              hash[:unconfirmed_transactions] = UnconfirmedTransaction.to_hash_collection(unconfirmed_address.transactions)
            end

            hash[:transactions] = Transaction.to_hash_collection(address.transactions(options[:offset], options[:limit]))
          end

          collection << hash
        }

        return collection
      end

      def to_json(options={})
        to_hash(options).to_json
      end
    end
  end
end
