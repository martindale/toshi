module Toshi
  module Models
    class UnconfirmedTransaction < Sequel::Model

      MEMORY_POOL   = 1 # same rules for inclusion as bitcoind's memory pool (was individually relayed to us and is not in a
                        # main block yet, or is in a now disconnected former main branch block)
      ORPHAN_POOL   = 2 # same rules for inclusion as bitcoind's mapOrphanTransactions (missing inputs)
      CONFLICT_POOL = 3 # txs conflicted with another tx when adding them to the memory pool from a disconnected block

      POOL_TO_NAME_TABLE = {
        MEMORY_POOL   => 'memory',
        ORPHAN_POOL   => 'orphan',
        CONFLICT_POOL => 'conflict'
      }

      def pool_name
        POOL_TO_NAME_TABLE[pool] || "unkown"
      end

      def bitcoin_tx
        Bitcoin::P::Tx.new(UnconfirmedRawTransaction.where(hsh: hsh).first.payload)
      end

      def inputs
        UnconfirmedInput.where(hsh: hsh).order(:position)
      end

      def mark_spent_outputs
        # FIXME: there's probably a nicer way to do this with the interface
        query = "update unconfirmed_outputs
                        set spent = 't'
                        from (select unconfirmed_outputs.id as output_id
                                     from unconfirmed_outputs,
                                          unconfirmed_inputs
                                     where unconfirmed_inputs.hsh = '#{hsh}' and
                                           unconfirmed_inputs.prev_out = unconfirmed_outputs.hsh and
                                           unconfirmed_inputs.index = unconfirmed_outputs.position) as spent_outputs
                        where unconfirmed_outputs.id = spent_outputs.output_id"
        Toshi.db.run(query)
      end

      def outputs
        UnconfirmedOutput.where(hsh: hsh).order(:position)
      end

      def previous_outputs
        prev_outs = []
        # FIXME: I really need to knock this off and learn the Sequel gem.
        query = "select unconfirmed_outputs.id,
                        unconfirmed_outputs.hsh,
                        unconfirmed_outputs.amount,
                        unconfirmed_outputs.script,
                        unconfirmed_outputs.position,
                        unconfirmed_outputs.spent
                        from unconfirmed_outputs,
                             unconfirmed_inputs
                        where unconfirmed_inputs.hsh = '#{hsh}' and
                              unconfirmed_outputs.hsh = unconfirmed_inputs.prev_out and
                              unconfirmed_outputs.position = unconfirmed_inputs.index"
        Toshi.db.fetch(query).map{|row| UnconfirmedOutput.call(row) }
      end

      def self.mempool
        UnconfirmedTransaction.where(pool: MEMORY_POOL)
      end

      def is_coinbase?
        inputs_count == 1 && inputs.first.coinbase?
      end

      def is_orphan?
        pool == ORPHAN_POOL
      end

      def in_memory_pool?
        pool == MEMORY_POOL
      end

      def self.from_hsh(hash)
        UnconfirmedTransaction.where(hsh: hash).first
      end

      def self.create_inputs(tx)
        inputs = []
        tx.in.each_with_index{|input,tx_position|
          i = {
            prev_out: input.previous_output,
            index: input.prev_out_index,
            script: Sequel.blob(input.script),
            sequence: Sequel.blob(input.sequence),
            position: tx_position,
            hsh: tx.hash,
          }
          inputs << i
        }
        return inputs
      end

      def self.create_outputs(tx)
        outputs, addresses = [], []
        tx.out.each_with_index{|output, tx_position|
          script = Bitcoin::Script.new(output.script)
          addrs = (script.get_addresses rescue []).uniq
          o = {
            amount: output.value,
            script: Sequel.blob(output.script),
            type: (script.type.to_s rescue 'unknown'),
            position: tx_position,
            hsh: tx.hash,
            spent: false
          }
          outputs << o
          addresses << addrs
        }
        return [ outputs, addresses ]
      end

      def self.upsert_output_addresses(transaction_id, outputs, output_ids, addresses)
        all_addresses = addresses.flatten.uniq
        existing_address_ids = {}

        # update existing addresses
        if all_addresses.any?
          UnconfirmedAddress.where(address: all_addresses).each{|address|
            existing_address_ids[address.address] = address.id
          }
        end

        # batch up new addresses and record output indexes
        output_indexes, new_addresses = {}, {}
        addresses.each_with_index{|addrs, index|
          if addrs.empty?
            output_indexes['unknown'] ||= []
            output_indexes['unknown'] << index
          else
            addrs.each{|address|
              output_indexes[address] ||= []
              output_indexes[address] << index
              if !existing_address_ids[address] && !new_addresses[address]
                output = outputs[index]
                a = {
                  address: address,
                  hash160: Bitcoin.hash160_from_address(address),
                  balance: 0,
                  address_type: (output[:type] == "p2sh") ? Address::P2SH_TYPE : Address::HASH160_TYPE,
                }
                new_addresses[address] = a
              end
            }
          end
        }

        # bulk import new addresses
        address_ids = UnconfirmedAddress.multi_insert(new_addresses.values, {:return => :primary_key})

        # create associations and ledger entries
        address_index, associations, entries = 0, [], []
        new_addresses.each_key{|addr|
          output_indexes[addr].each{|output_index|
            output = outputs[output_index]
            associations << {
              output_id: output_ids[output_index], address_id: address_ids[address_index]
            }
            # build ledger entry
            entries << {
              address_id: address_ids[address_index],
              transaction_id: transaction_id,
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }
          }
          address_index += 1
        }
        existing_address_ids.each{|addr, addr_id|
          output_indexes[addr].each{|output_index|
            output = outputs[output_index]
            associations << {
              output_id: output_ids[output_index], address_id: addr_id
            }
            # build ledger entry
            entries << {
              address_id: addr_id,
              transaction_id: transaction_id,
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }

          }
        }

        if output_indexes['unknown']
          # create entries for unknown addresses
          output_indexes['unknown'].each{|output_index|
            output = outputs[output_index]
            entries << {
              address_id: nil,
              transaction_id: transaction_id,
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }
          }
        end

        # bulk import associations
        Toshi.db[:unconfirmed_addresses_outputs].multi_insert(associations)

        # bulk import ledger entries
        Toshi.db[:unconfirmed_ledger_entries].multi_insert(entries)
      end

      def update_unconfirmed_ledger_for_inputs(tx, output_cache)
        # already updated.
        return if Toshi.db[:unconfirmed_ledger_entries]
        .where(transaction_id: id).exclude(input_id: nil).any?

        # gather these
        input_ids = self.inputs.select_map(:id)

        # create a cache for unconfirmed previous outputs
        unconfirmed_prev_outs = Toshi::OutputsCache.new
        previous_outputs.each{|output|
          txout = Bitcoin::Protocol::TxOut.new(output.amount, output.script)
          binary_hash = Toshi::Utils.hex_to_bin_hash(output.hsh)
          unconfirmed_prev_outs.set_output_for_outpoint(binary_hash, output.position, txout)
        }

        # figure out addresses
        addresses = []
        tx.inputs.each_with_index{|input, index|
          addrs = []
          if !input.coinbase?
            prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
            prev_out ||= unconfirmed_prev_outs.output_for_outpoint(input.prev_out, input.prev_out_index)
            raise "BUG: somehow we've accepted an orphan tx into the mempool" if !prev_out
            script = Bitcoin::Script.new(prev_out.script)
            addrs = (script.get_addresses rescue []).uniq
          end
          addresses << addrs
        }

        all_addresses = addresses.flatten.uniq
        existing_address_ids = {}

        if all_addresses.any?
          UnconfirmedAddress.where(address: all_addresses).each{|address|
            existing_address_ids[address.address] = address.id
          }
        end

        # batch up new addresses and record input indexes
        input_indexes, new_addresses = {}, {}
        addresses.each_with_index{|addrs, index|
          if addrs.empty?
            input_indexes['unknown'] ||= []
            input_indexes['unknown'] << index
          else
            addrs.each{|address|
              input_indexes[address] ||= []
              input_indexes[address] << index
              if !existing_address_ids[address] && !new_addresses[address]
                input = tx.inputs[index]
                prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
                prev_out ||= unconfirmed_prev_outs.output_for_outpoint(input.prev_out, input.prev_out_index)
                script = Bitcoin::Script.new(prev_out.script)
                type = (script.type.to_s rescue 'unknown')
                a = {
                  address: address,
                  hash160: Bitcoin.hash160_from_address(address),
                  address_type: (type == "p2sh") ? Address::P2SH_TYPE : Address::HASH160_TYPE,
                }
                new_addresses[address] = a
              end
            }
          end
        }

        # bulk import new addresses
        address_ids = UnconfirmedAddress.multi_insert(new_addresses.values, {:return => :primary_key})

        # create ledger entries
        address_index, entries = 0, []
        new_addresses.each_key{|addr|
          input_indexes[addr].each{|input_index|
            input = tx.inputs[input_index]
            prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
            prev_out ||= unconfirmed_prev_outs.output_for_outpoint(input.prev_out, input.prev_out_index)
            # build ledger entry
            entries << {
              address_id: address_ids[address_index],
              transaction_id: id,
              input_id: input_ids[input_index],
              output_id: nil,
              amount: prev_out.amount * -1
            }
          }
          address_index += 1
        }
        existing_address_ids.each{|addr, addr_id|
          input_indexes[addr].each{|input_index|
            input = tx.inputs[input_index]
            prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
            prev_out ||= unconfirmed_prev_outs.output_for_outpoint(input.prev_out, input.prev_out_index)
            # build ledger entry
            entries << {
              address_id: addr_id,
              transaction_id: id,
              input_id: input_ids[input_index],
              output_id: nil,
              amount: prev_out.amount * -1
            }

          }
        }

        if input_indexes['unknown']
          # create entries for unknown addresses
          input_indexes['unknown'].each{|input_index|
            input = tx.inputs[input_index]
            prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
            prev_out ||= unconfirmed_prev_outs.output_for_outpoint(input.prev_out, input.prev_out_index)
            entries << {
              address_id: nil,
              transaction_id: id,
              input_id: input_ids[input_index],
              output_id: nil,
              # FIXME: broken for coinbases
              amount: (prev_out ? prev_out.amount * -1 : 0)
            }
          }
        end

        # bulk import ledger entries
        Toshi.db[:unconfirmed_ledger_entries].multi_insert(entries)
      end

      def to_hash
        self.class.to_hash_collection([self]).first
      end

      def self.to_hash_collection(transactions)
        return [] unless transactions.any?
        transaction_ids = transactions.map{|transaction| transaction.id }

        input_ids, output_ids = [], []
        input_amounts, input_address_ids, output_address_ids = {}, {}, {}

        # gather inputs and outputs
        Toshi.db[:unconfirmed_ledger_entries].where(transaction_id: transaction_ids).each{|entry|
          transaction_id = entry[:transaction_id]
          if entry[:input_id]
            input_id = entry[:input_id]
            input_ids << input_id
            input_address_ids[input_id] ||= []
            input_address_ids[input_id] << entry[:address_id]
            input_amounts[input_id] = entry[:amount] * -1
          else
            output_id = entry[:output_id]
            output_ids << output_id
            output_address_ids[output_id] ||= []
            output_address_ids[output_id] << entry[:address_id]
          end
        }

        inputs_by_hsh = {}
        UnconfirmedInput.where(id: input_ids).each{|input|
          inputs_by_hsh[input.hsh] ||= []
          inputs_by_hsh[input.hsh] << input
        }

        outputs_by_hsh = {}
        UnconfirmedOutput.where(id: output_ids).each{|output|
          outputs_by_hsh[output.hsh] ||= []
          outputs_by_hsh[output.hsh] << output
        }

        # gather addresses
        addresses = {}
        address_ids = input_address_ids.values.flatten + output_address_ids.values.flatten
        UnconfirmedAddress.where(id: address_ids.uniq).each{|address| addresses[address.id] = address }

        txs = []

        # construct the hashes
        transactions.each{|transaction|
          tx = {}
          tx[:hash] = transaction.hsh
          #tx[:nid] = transaction.bitcoin_tx.normalized_hash # TODO: add
          tx[:version] = transaction.ver
          tx[:lock_time] = transaction.lock_time
          tx[:size] = transaction.size

          # inputs
          tx[:inputs] = []
          if inputs_by_hsh.any?
            inputs = inputs_by_hsh[transaction.hsh].sort_by{|input| input.position}
            inputs.each{|input|
              parsed_script = Bitcoin::Script.new(input.script)
              i = {}
              i[:previous_transaction_hash] = input.prev_out
              i[:output_index] = input.index
              i[:sequence] = input.sequence.unpack("V")[0] if input.sequence != Bitcoin::P::TxIn::DEFAULT_SEQUENCE
              if input.coinbase?
                i[:amount] = input_amounts[input.id]
                i[:coinbase] = input.script.unpack("H*")[0]
              else
                i[:amount] = input_amounts[input.id]
                i[:script] = parsed_script.to_string
                i[:addresses] = input_address_ids[input.id].map{|address_id| address_id ? addresses[address_id].address : "unknown" }
              end
              tx[:inputs] << i
            }
          end

          # outputs
          tx[:outputs] = []
          if outputs_by_hsh.any?
            outputs = outputs_by_hsh[transaction.hsh].sort_by{|output| output.position}
            outputs.each{|output|
              parsed_script = Bitcoin::Script.new(output.script)
              o = {}
              o[:amount] = output.amount
              o[:spent] = output.spent
              o[:script] = parsed_script.to_string
              o[:script_hex] = output.script.unpack("H*")[0]
              o[:script_type] = parsed_script.type
              o[:addresses] = output_address_ids[output.id].map{|address_id| address_id ? addresses[address_id].address : "unknown" }
              tx[:outputs] << o
            }
          end

          tx[:amount] = transaction.total_out_value
          tx[:fees] = transaction.fee
          tx[:confirmations] = 0
          tx[:pool] = transaction.pool_name

          txs << tx
        }
        txs
      end

      def self.create_from_tx(tx, pool=MEMORY_POOL)
        if UnconfirmedRawTransaction.where(hsh: tx.hash).empty?
          UnconfirmedRawTransaction.new(hsh: tx.hash, payload: Sequel.blob(tx.payload)).save
        end

        fields = tx.additional_fields || {}

        t = {
          hsh: tx.hash,
          ver: tx.ver,
          lock_time: tx.lock_time,
          size: tx.payload.size,
          pool: pool,
          total_in_value: fields[:total_in_value] || 0,
          total_out_value: fields[:total_out_value] || 0,
          fee: fields[:fee] || 0,
          inputs_count: tx.inputs.size,
          outputs_count: tx.outputs.size,
        }

        transaction = UnconfirmedTransaction.create(t)

        # create outputs
        outputs, addresses = create_outputs(tx)

        # create inputs
        inputs = create_inputs(tx)

        output_ids = UnconfirmedOutput.multi_insert(outputs, {:return => :primary_key})
        upsert_output_addresses(transaction.id, outputs, output_ids, addresses)

        UnconfirmedInput.multi_insert(inputs)

        transaction
      end

      # cleanup
      def before_destroy
        output_ids = Toshi.db[:unconfirmed_outputs].where(hsh: hsh).select_map(:id)
        Toshi.db[:unconfirmed_addresses_outputs].where(output_id: output_ids).delete
        Toshi.db[:unconfirmed_ledger_entries].where(transaction_id: id).delete
        Toshi.db[:unconfirmed_outputs].where(id: output_ids).delete
        Toshi.db[:unconfirmed_inputs].where(hsh: hsh).delete
      end

      # See: https://wiki.postgresql.org/wiki/Slow_Counting
      def self.total_count
        res = Toshi.db.fetch("SELECT reltuples AS total FROM pg_class WHERE relname = 'unconfirmed_transactions'").first
        res[:total].to_i
      end
    end
  end
end
