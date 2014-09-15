module Toshi
  module Models
    class UnconfirmedAddress < Sequel::Model

      many_to_many :unconfirmed_outputs,
                   :left_key => :address_id,
                   :right_key => :output_id,
                   :join_table => :unconfirmed_addresses_outputs

      # unconfirmed balance
      def balance
        balance = 0
        if a = Address.where(address: address).first
          # confirmed balance
          balance = a.balance
          # subtract unconfirmed spends of confirmed outputs
          balance -= amount_confirmed_spent_by_unconfirmed(a)
        end

        # add unconfirmed unspent outputs
        if unconfirmed_unspent = unspent_outputs.sum(:amount).to_i
          balance += unconfirmed_unspent
        end

        balance
      end

      def amount_confirmed_spent_by_unconfirmed(address)
        query = "select sum(outputs.amount) as total
                        from outputs,
                             addresses_outputs,
                             unconfirmed_inputs
                        where unconfirmed_inputs.prev_out = outputs.hsh and
                              unconfirmed_inputs.index = outputs.position and
                              addresses_outputs.address_id = #{address.id} and
                              addresses_outputs.output_id = outputs.id and
                              outputs.branch = #{Block::MAIN_BRANCH}"
        query = Toshi.db.fetch(query).first
        query[:total].to_i
      end

      def outputs
        unconfirmed_outputs_dataset
      end

      def unspent_outputs
        unconfirmed_outputs_dataset.where(spent: false)
      end

      def spent_outputs
        unconfirmed_outputs_dataset.where(spent: true)
      end

      HASH160_TYPE = 0
      P2SH_TYPE    = 1

      def type
        case address_type
        when HASH160_TYPE; :hash160
        when P2SH_TYPE;    :p2sh
        end
      end

      def transactions(offset=0, limit=100)
        tids = Toshi.db[:unconfirmed_ledger_entries].where(address_id: id)
          .join(:unconfirmed_transactions, :id => :transaction_id).where(pool: UnconfirmedTransaction::MEMORY_POOL)
          .select(:transaction_id).group_by(:transaction_id).order(Sequel.desc(:transaction_id))
          .offset(offset).limit(limit).map(:transaction_id)
        return [] unless tids.any?
        UnconfirmedTransaction.where(id: tids).order(Sequel.desc(:id))
      end

    end
  end
end
