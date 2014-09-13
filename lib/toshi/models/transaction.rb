module Toshi
  module Models
    class Transaction < Sequel::Model

      TIP_POOL      = 1 # same rules for inclusion as bitcoind's pcoinsTip view (on the main branch)
      BLOCK_POOL    = 2 # txs only associated with non-main branch blocks
      CONFLICT_POOL = 3 # conflicts

      POOL_TO_NAME_TABLE = {
        TIP_POOL      => 'tip',
        BLOCK_POOL    => 'block',
        CONFLICT_POOL => 'conflict'
      }

      many_to_many :blocks

      def block
        blocks_dataset.where(branch: Block::MAIN_BRANCH).first
      end

      def pool_name
        POOL_TO_NAME_TABLE[pool] || "unknown"
      end

      def bitcoin_tx
        Bitcoin::P::Tx.new(RawTransaction.where(hsh: hsh).first.payload)
      end

      def confirmations
        block.confirmations rescue 0
      end

      def inputs
        Input.where(hsh: hsh).order(:position)
      end

      def outputs
        Output.where(hsh: hsh).order(:position)
      end

      def is_coinbase?
        inputs_count == 1 && inputs.first.coinbase?
      end

      def in_view?
        pool == TIP_POOL
      end

      def in_orphan_block?
        blocks_dataset.where(branch: Block::ORPHAN_BRANCH).any?
      end

      def raw
        Toshi::Models::RawTransaction.where(hsh: hsh).first
      end

      def self.from_hsh(hash)
        Transaction.where(hsh: hash).first
      end

      def self.create_inputs(tx, branch, output_cache)
        inputs, addresses = [], []
        tx.in.each_with_index{|input,tx_position|
          addrs = []
          if !input.coinbase?
            prev_out = output_cache.output_for_outpoint(input.prev_out, input.prev_out_index)
            if prev_out
              script = Bitcoin::Script.new(prev_out.script)
              addrs = (script.get_addresses rescue []).uniq
            elsif branch != Block::ORPHAN_BRANCH
              # this is expected only for txs in orphan blocks
              raise "BUG: can't find previous output!"
            end
          end
          i = {
            prev_out: input.previous_output,
            index: input.prev_out_index,
            script: Sequel.blob(input.script),
            # doesn't work. needs redeeming output script to get type
            #type: (Bitcoin::Script.new(input.script).type.to_s rescue "unkown"),
            sequence: Sequel.blob(input.sequence),
            position: tx_position,
            hsh: tx.hash,
          }
          inputs << i
          addresses << addrs
        }
        return [ inputs, addresses ]
      end

      def self.create_outputs(tx, branch, output_cache)
        outputs, addresses = [], []
        tx.out.each_with_index{|output, tx_position|
          script = Bitcoin::Script.new(output.script)
          addrs = (script.get_addresses rescue []).uniq
          spent = output_cache.outpoint_is_spent(tx.binary_hash, tx_position)
          o = {
            amount: output.value,
            script: Sequel.blob(output.script),
            type: (script.type.to_s rescue 'unknown'),
            position: tx_position,
            hsh: tx.hash,
            branch: branch,
            spent: spent == true # can be nil
          }
          outputs << o
          addresses << addrs
        }
        return [ outputs, addresses ]
      end

      def self.upsert_output_addresses(tx_hsh_to_id, output_ids, outputs, addresses, branch)
        all_addresses = addresses.flatten.uniq
        existing_address_ids = {}

        # find existing addresses
        if all_addresses.any?
          Address.where(address: all_addresses).each{|address|
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
                  address_type: (output[:type] == "p2sh") ? Address::P2SH_TYPE : Address::HASH160_TYPE,
                }
                new_addresses[address] = a
              end
            }
          end
        }

        # bulk import new addresses
        address_ids = Address.multi_insert(new_addresses.values, {:return => :primary_key})

        # create associations and address ledger entries
        address_index, associations, ledger_entries, unspent_outputs = 0, [], [], []
        new_addresses.each_key{|addr|
          output_indexes[addr].each{|output_index|
            output = outputs[output_index]
            associations << { output_id: output_ids[output_index], address_id: address_ids[address_index] }
            ledger_entries << {
              address_id: address_ids[address_index],
              transaction_id: tx_hsh_to_id[output[:hsh]],
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }
            # utxo set
            if !output[:spent] && output[:branch] == Block::MAIN_BRANCH
              unspent_outputs << {
                output_id: output_ids[output_index],
                amount: output[:amount],
                address_id: address_ids[address_index]
              }
            end
          }
          address_index += 1
        }
        existing_address_ids.each{|addr, addr_id|
          output_indexes[addr].each{|output_index|
            output = outputs[output_index]
            associations << { output_id: output_ids[output_index], address_id: addr_id }
            ledger_entries << {
              address_id: addr_id,
              transaction_id: tx_hsh_to_id[output[:hsh]],
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }
            # utxo set
            if !output[:spent] && output[:branch] == Block::MAIN_BRANCH
              unspent_outputs << {
                output_id: output_ids[output_index],
                amount: output[:amount],
                address_id: addr_id
              }
            end
          }
        }

        if output_indexes['unknown']
          # create entries for unknown addresses
          output_indexes['unknown'].each{|output_index|
            output = outputs[output_index]
            # associations
            associations << { output_id: output_ids[output_index], address_id: nil }
            # address ledger
            ledger_entries << {
              address_id: nil,
              transaction_id: tx_hsh_to_id[output[:hsh]],
              input_id: nil,
              output_id: output_ids[output_index],
              amount: output[:amount]
            }
            # utxo set
            if !output[:spent] && output[:branch] == Block::MAIN_BRANCH
              unspent_outputs << {
                output_id: output_ids[output_index],
                amount: output[:amount],
                address_id: nil
              }
            end
          }
        end

        # bulk import associations
        Toshi.db[:addresses_outputs].multi_insert(associations)

        # bulk update the address ledger for block explorers
        Toshi.db[:address_ledger_entries].multi_insert(ledger_entries)

        # bulk add new outputs to the utxo set
        Toshi.db[:unspent_outputs].multi_insert(unspent_outputs)
      end

      def self.update_address_ledger_for_inputs(tx_hsh_to_id, input_ids, inputs, addresses, output_cache, branch, block_fees=0)
        all_addresses = addresses.flatten.uniq
        address_ids = {}

        # get the address ids
        if all_addresses.any?
          Address.where(address: all_addresses).each{|address|
            address_ids[address.address] = address.id
          }
        end

        # create a list of indexes into the input array for each address
        input_indexes = {}
        addresses.each_with_index{|addrs, index|
          if addrs.empty?
            input_indexes['unknown'] ||= []
            input_indexes['unknown'] << index
          else
            addrs.each{|address|
              input_indexes[address] ||= []
              input_indexes[address] << index
            }
          end
        }

        # create address ledger entries for known addresses
        address_index, entries = 0, []
        address_ids.each{|addr, addr_id|
          input_indexes[addr].each{|input_index|
            input = inputs[input_index]
            binary_hash = [input[:prev_out]].pack('H*').reverse
            output = output_cache.output_for_outpoint(binary_hash, input[:index])
            entries << {
              address_id: addr_id,
              transaction_id: tx_hsh_to_id[input[:hsh]],
              input_id: input_ids[input_index],
              output_id: nil,
              amount: output.amount * -1,
            }
          }
        }

        if input_indexes['unknown']
          # create entries for unknown addresses
          input_indexes['unknown'].each{|input_index|
            input, amount = inputs[input_index], 0
            if input[:index] == 0xffffffff && input[:prev_out] == Input::INPUT_COINBASE_HASH
              # handle coinbase inputs
              tx = Transaction.from_hsh(input[:hsh])
              amount = (tx.total_out_value - block_fees) * -1
            else
              binary_hash = [input[:prev_out]].pack('H*').reverse
              output = output_cache.output_for_outpoint(binary_hash, input[:index])
              # we may not have the output but still need to create a ledger entry.
              # otherwise we won't display orphans properly with the API.
              # we'll fix the entry if we find the previous output.
              amount = output ? output.amount * -1 : 0
            end
            entries << {
              address_id: nil,
              transaction_id: tx_hsh_to_id[input[:hsh]],
              input_id: input_ids[input_index],
              output_id: nil,
              amount: amount
            }
          }
        end

        # bulk update the address ledger for block explorers
        Toshi.db[:address_ledger_entries].multi_insert(entries)
      end

      def self.multi_insert_inputs(tx_hsh_to_id, inputs, addresses, output_cache, branch, spent_outpoint_to_id, block_fees=0)
        # batch import inputs
        input_ids = Input.multi_insert(inputs, {:return => :primary_key})

        # update the address ledger table
        update_address_ledger_for_inputs(tx_hsh_to_id, input_ids, inputs, addresses, output_cache, branch, block_fees)

        # record spending inputs in the join table
        spending_inputs = []
        inputs.each_with_index{|input,index|
          next if input[:index] == 0xffffffff && input[:prev_out] == Input::INPUT_COINBASE_HASH
          # add entries for outputs we just created
          if prev_tx = spent_outpoint_to_id[input[:prev_out]]
            if prev_tx[input[:index]]
              spending_inputs << {
                input_id: input_ids[index],
                output_id: prev_tx[input[:index]]
              }
            end
          else
            # add entries for existing outputs
            binary_hash = Toshi::Utils.hex_to_bin_hash(input[:prev_out])
            output = output_cache.output_from_model_cache(binary_hash, input[:index])
            if output && output.is_on_main_chain?
              spending_inputs << {
                input_id: input_ids[index],
                output_id: output.id
              }
            elsif Block::MAIN_BRANCH == branch
              raise "BUG: missing previous output!"
            end
          end
        }

        Toshi.db[:spending_inputs].multi_insert(spending_inputs)
      end

      def self.multi_insert_outputs(tx_hsh_to_id, outputs, addresses, branch, spent_outpoint_to_id)
        # batch import outputs first then handle the addresses
        output_ids = Output.multi_insert(outputs, {:return => :primary_key})

        # this will also handle updating the address ledger table
        upsert_output_addresses(tx_hsh_to_id, output_ids, outputs, addresses, branch)

        # save these for spending inputs
        outputs.each_with_index{|output,index|
          if output[:spent]
            spent_outpoint_to_id[output[:hsh]] ||= []
            spent_outpoint_to_id[output[:hsh]] << output_ids[index]
          end
        }
      end

      # we might not have been able to add a ledger entry for missing inputs
      # in the case of orphan transactions. this handles that.
      def self.update_address_ledger_for_missing_inputs(tx_ids, output_cache)
        # figure out which ones are missing complete ledger entries.
        # they'll have a 0 amount.
        input_ids, ledger_entry_ids = [], []
        Toshi.db[:address_ledger_entries].where(transaction_id: tx_ids.values)
          .exclude(input_id: nil).where(amount: 0).each{|entry|
          input_ids << entry[:input_id]
          ledger_entry_ids << entry[:id]
        }

        # all there
        return if input_ids.empty?

        # delete these for re-add
        Toshi.db[:address_ledger_entries].where(id: ledger_entry_ids).delete

        # gather inputs and their ids
        inputs_by_id = {}
        Input.where(id: input_ids).each{|input| inputs_by_id[input.id] = input }

        # gather output ids and their associated address ids
        output_ids, address_ids = {}, {}
        inputs_by_id.each_value{|input|
          binary_hash = [input.prev_out].pack('H*').reverse
          output = output_cache.output_from_model_cache(binary_hash, input.index)
          raise "BUG: missing previous output!" if !output
          output_ids[input.id] = output.id
        }
        Toshi.db[:addresses_outputs].where(output_id: output_ids.values).each{|entry|
          address_ids[entry[:output_id]] ||= []
          address_ids[entry[:output_id]] << entry[:address_id]
        }

        # add entries for the formerly missing previous output info
        entries = []
        inputs_by_id.each_value{|input|
          binary_hash = [input.prev_out].pack('H*').reverse
          output = output_cache.output_for_outpoint(binary_hash, input.index)
          raise "BUG: missing previous output!" if !output
          output_id = output_ids[input.id]
          address_ids[output_id].each{|address_id|
            entries << {
              address_id: address_id,
              transaction_id: tx_ids[input.hsh],
              input_id: input.id,
              output_id: nil,
              amount: output.amount * -1,
            }
          }
        }

        # add the updated entries
        Toshi.db[:address_ledger_entries].multi_insert(entries)
      end

      def update_address_ledger_for_coinbase(block_reward)
        Toshi.db[:address_ledger_entries].where(transaction_id: id).where(amount: 0)
          .where(input_id: inputs.first.id).update(:amount => (block_reward * -1))
      end

      def self.create_from_tx(tx, pool, branch, output_cache=nil, block=nil, index=0)
        RawTransaction.new(hsh: tx.hash, payload: Sequel.blob(tx.payload)).save unless !RawTransaction.where(hsh: tx.hash).empty?

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
          height: ((block && block.is_main_chain?) ? block.height : 0)
        }

        # this should only be nil in tests
        output_cache = Toshi::OutputsCache.new if !output_cache

        # create outputs first
        outputs, output_addresses = create_outputs(tx, branch, output_cache)

        # then create inputs
        inputs, input_addresses = create_inputs(tx, branch, output_cache)

        # if we're persisting txs for a block hold off importing
        # txs, inputs, and outputs until we can do them all at once
        return [t, inputs, input_addresses, outputs, output_addresses] if block

        # or else insert them all now and return a Transaction model
        transaction = Transaction.create(t)
        tx_hsh_to_id = { transaction.hsh => transaction.id }

        spent_outpoint_to_id = {}
        multi_insert_outputs(tx_hsh_to_id, outputs, output_addresses, branch, spent_outpoint_to_id)
        multi_insert_inputs(tx_hsh_to_id, inputs, input_addresses, output_cache, branch, spent_outpoint_to_id)

        transaction
      end

      def to_hash(options = {})
        options[:show_block_info] ||= true
        self.class.to_hash_collection([self], options).first
      end

      # 6 queries per transaction array (9 if block info also requested)
      def self.to_hash_collection(transactions, options = {})
        return [] unless transactions.any?

        options[:show_block_info] ||= true

        transaction_ids = transactions.map{|transaction| transaction.id }

        # gather blocks
        block_ids = []
        transaction_block_ids, blocks_by_transaction_id = {}, {}
        if options[:show_block_info]
          Toshi.db[:blocks_transactions].where(transaction_id: transaction_ids).each{|entry|
            block_ids << entry[:block_id]
            transaction_block_ids[entry[:block_id]] ||= []
            transaction_block_ids[entry[:block_id]] << entry[:transaction_id]
          }
          Block.where(id: block_ids.uniq, branch: Block::MAIN_BRANCH).each{|block|
            transaction_block_ids[block.id].each{|transaction_id|
              blocks_by_transaction_id[transaction_id] = block
            }
          }
        end

        input_ids, output_ids = [], []
        input_amounts, input_address_ids, output_address_ids = {}, {}, {}

        # gather inputs and outputs
        Toshi.db[:address_ledger_entries].where(transaction_id: transaction_ids).each{|entry|
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
        Input.where(id: input_ids).each{|input|
          inputs_by_hsh[input.hsh] ||= []
          inputs_by_hsh[input.hsh] << input
        }

        outputs_by_hsh, spent_output_ids, unspent_output_ids = {}, [], []
        Output.where(id: output_ids).each{|output|
          outputs_by_hsh[output.hsh] ||= []
          outputs_by_hsh[output.hsh] << output
          if output.spent
            spent_output_ids << output.id
          else
            # they may be unconfirmed spent though.
            unspent_output_ids << output.id
          end
        }

        # gather spending inputs of any spent outputs
        spending_input_by_output_id = {}
        fetch_spending_inputs(spent_output_ids, unspent_output_ids, spending_input_by_output_id)

        # gather addresses
        addresses = {}
        address_ids = input_address_ids.values.flatten + output_address_ids.values.flatten
        Address.where(id: address_ids.uniq).each{|address| addresses[address.id] = address }

        txs = []

        # this is a query
        max_height = options[:show_block_info] ? Block.max_height : 0

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
          # NOTE: orphan tx inputs will show 0 amount from "unknown" address
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

          # outputs
          tx[:outputs] = []
          outputs = outputs_by_hsh[transaction.hsh].sort_by{|output| output.position}
          outputs.each{|output|
            parsed_script = Bitcoin::Script.new(output.script)
            o = {}
            o[:amount] = output.amount
            o[:spent] = output.spent
            if input = spending_input_by_output_id[output.id]
              # NOTE: spent will be false if this is an unconfirmed spend
              o[:spending_transaction_hash] = input.hsh
              o[:input_index] = input.position
            end
            o[:script] = parsed_script.to_string
            o[:script_hex] = output.script.unpack("H*")[0]
            o[:script_type] = parsed_script.type
            o[:addresses] = output_address_ids[output.id].map{|address_id| address_id ? addresses[address_id].address : "unknown" }
            tx[:outputs] << o
          }

          tx[:amount] = transaction.total_out_value
          tx[:fees] = transaction.fee

          if options[:show_block_info]
            if block = blocks_by_transaction_id[transaction.id]
              tx[:confirmations] = block.confirmations(max_height)
              tx[:block_height] = transaction.height if transaction.height > 0
              tx[:block_hash] = block.hsh
              tx[:block_time] = Time.at(block.time).utc.iso8601
              tx[:block_branch] = block.branch_name
            end
          end

          txs << tx
        }
        txs
      end

      # 2 queries: confirmed and unconfirmed
      def self.fetch_spending_inputs(spent_output_ids, unspent_output_ids, spending_input_by_output_id)
        if spent_output_ids.any?
          sql_values = spent_output_ids.to_s.gsub('[', '(').gsub(']', ')')
          # First find confirmed spends.
          query = "select inputs.id as id,
                          inputs.hsh as hsh,
                          inputs.prev_out as prev_out,
                          inputs.index as index,
                          inputs.script as script,
                          inputs.sequence as sequence,
                          inputs.position as position,
                          spending_inputs.output_id as output_id
                          from inputs, spending_inputs
                          where spending_inputs.output_id in #{sql_values} and
                                inputs.id = spending_inputs.input_id"
          Toshi.db.fetch(query).each{|row|
            output_id = row.delete(:output_id)
            spending_input_by_output_id[output_id] = Input.call(row)
          }
        end

        if unspent_output_ids.any?
          sql_values = unspent_output_ids.to_s.gsub('[', '(').gsub(']', ')')
          # Now find any unconfirmed spends.
          query = "select unconfirmed_inputs.id as id,
                          unconfirmed_inputs.hsh as hsh,
                          unconfirmed_inputs.prev_out as prev_out,
                          unconfirmed_inputs.index as index,
                          unconfirmed_inputs.script as script,
                          unconfirmed_inputs.sequence as sequence,
                          unconfirmed_inputs.position as position,
                          outputs.id as output_id
                          from unconfirmed_inputs, outputs, unconfirmed_transactions
                          where outputs.id in #{sql_values} and
                                unconfirmed_inputs.prev_out = outputs.hsh and
                                unconfirmed_inputs.index = outputs.position and
                                unconfirmed_transactions.hsh = unconfirmed_inputs.hsh and
                                unconfirmed_transactions.pool = #{UnconfirmedTransaction::MEMORY_POOL}"
          Toshi.db.fetch(query).each{|row|
            output_id = row.delete(:output_id)
            # Note that we're mixing models in this hash.
            spending_input_by_output_id[output_id] = UnconfirmedInput.call(row)
          }
        end
      end

      def to_json(options={})
        to_hash(options).to_json
      end

      # This is much faster than a count(*) on the table.
      # See: https://wiki.postgresql.org/wiki/Slow_Counting
      def self.total_count
        res = Toshi.db.fetch("SELECT reltuples AS total FROM pg_class WHERE relname = 'transactions'").first
        res[:total].to_i
      end
    end
  end
end
