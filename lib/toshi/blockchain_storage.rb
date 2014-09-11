module Toshi
  # Blockchain storage using Sequel/PostgreSQL as a backend.
  # Also uses an in-memory index of block headers.
  class BlockchainStorage
    include Logging

    def initialize(output_cache)
      @output_cache = output_cache
      @block_index = Toshi::BlockHeaderIndex.new
      @block_index.item_limit = 2016
      @block_index.storage = self
      self.current_block= nil
      load_genesis_block
    end

    # Load the appropriate genesis block for the current network.
    def load_genesis_block
      self.transaction({}) do
        genesis_hash = Bitcoin.network[:genesis_hash]
        if ([:regtest, :mainnet].include?(Bitcoin.network_name) ||
            ![:test].include?(Toshi.env)) &&
            Toshi::Models::Block.head == nil &&
            Toshi::Models::Block.where(hsh: genesis_hash).empty?
          logger.info{ "Inserting genesis block #{genesis_hash}" }
          path_to_genesis_block = "config/blocks/#{genesis_hash}.json"
          genesis_block = Bitcoin::Protocol::Block.from_json_file(path_to_genesis_block)
          self.save_block_on_main_branch(genesis_block, 0)
        end
      end
    end

    # Block processing must see a consistent view of the data throughout all validation steps.
    # Transaction should provide that isolated view and atomic application of all changes.
    def transaction(opts={}, &blk)
      Toshi.db.transaction(opts, &blk)
    end

    # Returns true if the block is either on main branch or side branch.
    def is_block_processed?(hash)
      # we try to reprocess orphans
      Toshi::Models::Block.where(hsh: hash).exclude(branch: Toshi::Models::Block::ORPHAN_BRANCH).any?
    end

    # Returns true if block is included in the mainchain or resides on the sidechain.
    # Orphan blocks are not valid.
    def is_block_valid?(hash)
      if @block_index.block_header_in_index?(hash)
        return true
      end
      !Toshi::Models::Block.main_or_side_branch.where(hsh: hash).empty?
    end

    def is_block_orphan?(hash)
      !Toshi::Models::Block.orphan_branch.where(hsh: hash).empty?
    end

    def remove_block_header(block)
      @block_index.remove_block(block)
    end

    # Returns the height of the processed block (mainchain, sidechain or orphan)
    # Returns nil if block not found.
    def height_for_block(hash)
      height = guard_block_index_access do
        bh = @block_index.block_header_for_hash(hash)
        bh && bh.height
      end
      return height if height
      b = Toshi::Models::Block.where(hsh: hash).first
      b ? b.height : nil
    end

    # Returns Bitcoin::Protocol::Block or nil.
    # Block could be in the mainchain/sidechain or orphan.
    # Only returns more-or-less validated blocks, not raw blocks.
    def processed_block_for_hash(hash)
      if Toshi::Models::Block.where(hsh: hash).empty?
        return nil
      end
      stored_block = Toshi::Models::RawBlock.where(hsh: hash).first
      if !stored_block
        return nil
      end
      Bitcoin::Protocol::Block.new(stored_block.payload)
    end

    # Returns Bitcoin::Protocol::Block or nil
    # Only if it is a valid block on main chain or side chain.
    # Orphan block is not returned.
    def valid_block_for_hash(hash)
      if !Toshi::Models::Block.main_or_side_branch.where(hsh: hash).first
        return nil
      end
      stored_block = Toshi::Models::RawBlock.where(hsh: hash).first
      if !stored_block
        return nil
      end
      Bitcoin::Protocol::Block.new(stored_block.payload)
    end

    # Returns Bitcoin::Protocol::Block or nil.
    def orphan_block_for_hash(hash)
      if Toshi::Models::Block.orphan_branch.where(hsh: hash).empty?
        return nil
      end
      stored_block = Toshi::Models::RawBlock.where(hsh: hash).first
      if !stored_block
        return nil
      end
      Bitcoin::Protocol::Block.new(stored_block.payload)
    end

    # Store raw block (with unknown status: could be completely invalid)
    def store_raw_block(block)
      payload = block.payload || block.to_payload
      if Toshi::Models::RawBlock.where(hsh: block.hash).empty?
        Toshi::Models::RawBlock.new(hsh: block.hash, payload: payload).save
      end
    end

    # Loads raw block (with unknown status: could be completely invalid)
    def raw_block_for_hash(hash)
      stored_raw_block = Toshi::Models::RawBlock.where(hsh: hash).first
      if !stored_raw_block
        return nil
      end
      Bitcoin::Protocol::Block.new(stored_raw_block.payload)
    end

    # Returns a hash of latest block in the mainchain.
    # Returns nil if there are no blocks yet.
    def mainchain_tip_hash
      head = Toshi::Models::Block.head
      head ? head.hsh : nil
    end

    # Returns total work accumulated up to a given block (inclusive)
    # Should use BlockHeaderIndex for efficiency
    def total_work_up_to_block_hash(hash)
      work = guard_block_index_access do
        bh = @block_index.block_header_for_hash(hash)
        if bh.total_work && bh.total_work > 0
          bh.total_work
        else
          nil
        end
      end
      return work if work
      blk = Toshi::Models::Block.where(hsh: hash).first
      return 0 if !blk
      blk.block_work # Not to be confused with Bitcoin::Protocol::Block#block_work which is per-block work
    end

    # Saves the block as the main branch block at a given height.
    # Optional prev_work is used to calculate total work to store with this block.
    # FIXME: probably, it's not the best API yet, but it's compatible with the existing code
    # for now, so we'll keep it around for a while.
    def save_block_on_main_branch(block, height, prev_work = 0)
      @block_index.insert_block(block, height, prev_work)
      !!Toshi::Models::Block.create_from_block(block, height, Toshi::Models::Block::MAIN_BRANCH, @output_cache, prev_work)
      @output_cache.flush
    end

    def save_block_on_side_branch(block, height, prev_work = 0)
      @block_index.insert_block(block, height, prev_work)
      !!Toshi::Models::Block.create_from_block(block, height, Toshi::Models::Block::SIDE_BRANCH, @output_cache, prev_work)
      @output_cache.flush
    end

    # Block headers API

    # Returns an instance of BlockHeaderInterface (see above)
    # Only valid block headers are returned (main chain, side chain), not orphans.
    # Storage class may implement efficient in-memory structure holding all block headers.
    # By default it returns a full valid block for hash.
    def block_header_for_hash(hash)
      guard_block_index_access { @block_index.block_header_for_hash(hash) } || valid_block_for_hash(hash)
    end

    # Returns height for block_header. Allows to make it efficient if block_header stores height.
    # By default calls height_for_block()
    def height_for_block_header(block_header)
      bh = guard_block_index_access { @block_index.block_header_for_hash(block_header.hash) }
      return bh.height if bh && bh.height
      return height_for_block(block_header.hash)
    end

    # Returns previous block header. Allows to make it efficient if block_header caches a reference to a previous block.
    # By default calls block_header_for_hash(<prev hash>)
    def previous_block_header_for_block_header(block_header)
      bh = guard_block_index_access { block_header.previous_block_header }
      return bh if bh
      return block_header_for_hash(block_header.prev_block_hex)
    end

    # Returns total work accumulated up to a given block (inclusive)
    # By default calls total_work_up_to_block_hash(block_header.hash) (not very efficient)
    def total_work_up_to_block_header(block_header)
      tw = block_header.total_work
      return tw if tw && tw > 0
      return total_work_up_to_block_hash(block_header.hash)
    end

    # UTXO updates

    def current_block=(block)
      @current_block = block
      # {
      #   <txhash> => {
      #     :tx => Tx object,
      #     :spent_outputs => [ false, false, false, true, false, ... ]
      #   }
      # }
      @current_block_transactions_map = {}
      if @current_block
        # Reset all spent flags to false.
        @current_block.tx.each_with_index do |tx,position|
          @current_block_transactions_map[tx.hash] = {
            tx: tx,
            spent_outputs: (tx.outputs.map{|o| false }),
            position: position
          }
          raise "BUG: Sanity check: NO TX!" if !@current_block_transactions_map[tx.hash][:tx]
          raise "BUG: Sanity check: NO TX OUTPUTS!" if @current_block_transactions_map[tx.hash][:spent_outputs].size == 0
        end
      end
      return @current_block
    end

    def tx_in_current_block(hash)
      dict = @current_block_transactions_map[hash]
      return nil if !dict
      return dict[:tx]
    end

    def tx_position_in_current_block(hash)
      dict = @current_block_transactions_map[hash]
      return -1 if !dict
      return dict[:position]
    end

    def txout_in_current_block(hash, output_index)
      dict = @current_block_transactions_map[hash]
      return nil if !dict
      return dict[:tx].outputs[output_index]
    end

    def txout_spent_in_current_block(hash, output_index)
      dict = @current_block_transactions_map[hash]
      return nil if !dict
      return dict[:spent_outputs][output_index]
    end

    def self.add_to_utxo_set(output_ids)
      # FIXME: Figure out how to use the Sequel gem for this.
      # Raw SQL is fragile.
      sql_values = output_ids.to_s.gsub('[', '(').gsub(']', ')')
      query = "insert into unspent_outputs (output_id, amount, address_id) (
                 select outputs.id as output_id,
                        outputs.amount as amount,
                        addresses_outputs.address_id as address_id
                        from outputs, addresses_outputs
                        where outputs.id in #{sql_values} and
                              addresses_outputs.output_id = outputs.id
               )"
      Toshi.db.run(query)
    end

    def self.remove_from_utxo_set(output_ids)
      Toshi.db[:unspent_outputs].where(output_id: output_ids).delete
    end

    # This only affects in-memory cache.
    # Note: tx hash is raw binary, not hex.
    def mark_output_as_spent(binary_tx_hash, output_index)
      @output_cache.mark_output_as_spent(binary_tx_hash, output_index, true)

      # Also mark outputs in the current block
      hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)
      if dict = @current_block_transactions_map[hash]
        dict[:spent_outputs][output_index] = true
      end
    end

    # This only affects the database records.
    def mark_outputs_as_spent(output_ids)
      self.class.remove_from_utxo_set(output_ids)

      # mark these spent all at once
      Toshi::Models::Output.where(id: output_ids)
        .update(spent: true, branch: Toshi::Models::Block::MAIN_BRANCH)
    end

    # This only affects in-memory cache.
    # Note: tx hash is raw binary, not hex.
    def mark_output_as_unspent(binary_tx_hash, output_index)
      @output_cache.mark_output_as_spent(binary_tx_hash, output_index, false)

      # Also mark outputs in the current block
      hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)
      if dict = @current_block_transactions_map[hash]
        dict[:spent_outputs][output_index] = false
      end
    end

    # This only affects the database records.
    def mark_outputs_as_unspent(output_ids)
      self.class.add_to_utxo_set(output_ids)

      # mark these unspent all at once
      Toshi::Models::Output.where(id: output_ids)
        .update(spent: false, branch: Toshi::Models::Block::MAIN_BRANCH)
    end

    # Called when block is disconnected from the main chain.
    # This only affects in-memory cache.
    # The output should be removed or marked as not available.
    def mark_output_as_not_available(binary_tx_hash, output_index)
      @output_cache.mark_output_as_not_available(binary_tx_hash, output_index)
    end

    # This only affects the database records.
    def mark_outputs_as_unavailable(output_ids)
      self.class.remove_from_utxo_set(output_ids)

      # mark these as side branch outputs all at once
      Toshi::Models::Output.where(id: output_ids)
        .update(spent: false, branch: Toshi::Models::Block::SIDE_BRANCH)
    end

    # Update all the database records for outputs in a block.
    def update_outputs_on_connect_block(block)
      spent_output_ids, unspent_output_ids = [], []
      block.tx.each do |tx|
        if !tx.is_coinbase?
          tx.inputs.each do |txin|
            if output = self.output_from_model_cache(txin.prev_out, txin.prev_out_index)
              spent_output_ids << output.id
            end
          end
        end
        tx.outputs.each_with_index do |txout, index|
          if output = self.output_from_model_cache(tx.binary_hash, index)
            unspent_output_ids << output.id
          end
        end
      end

      mark_outputs_as_unspent(unspent_output_ids) if unspent_output_ids.any?
      mark_outputs_as_spent(spent_output_ids) if spent_output_ids.any?
    end

    # Update all the database records for outputs in a block.
    def update_outputs_on_disconnect_block(block)
      unspent_output_ids, unavailable_output_ids = [], []
      block.tx.each do |tx|
        if !tx.is_coinbase?
          tx.inputs.each do |txin|
            if output = self.output_from_model_cache(txin.prev_out, txin.prev_out_index)
              unspent_output_ids << output.id
            end
          end
        end
        tx.outputs.each_with_index do |txout, index|
          if output = self.output_from_model_cache(tx.binary_hash, index)
            unavailable_output_ids << output.id
          end
        end
      end

      mark_outputs_as_unspent(unspent_output_ids) if unspent_output_ids.any?
      mark_outputs_as_unavailable(unavailable_output_ids) if unavailable_output_ids.any?
    end

    # To implement BIP30, must be equivalent to (view.HaveCoins(hash) && !view.GetCoins(hash).IsPruned())
    # Return true if there is one unspent output for any of the transactions.
    def has_previously_unspent_outputs_for_any_tx(block)
      # Intentionally ignores current_block because the txs to test against are coming from it already.
      # No use for a partial cache here because the usual
      # It's allowed to exist in non-main branch blocks; this includes current block.
      block.tx.each{|tx|
        tx.out.each_with_index{|out,i|
          output = self.output_from_model_cache(tx.binary_hash, i)
          next if !output || output.spent || !output.is_on_main_chain?
          logger.debug{ "BIP30 violation, output: #{output.hsh}:#{output.position}, branch: #{output.branch}" }
          return true
        }
      }
      false
    end

    # return a cached copy of the output model
    # this will populate the cache from the db if possible
    def output_from_model_cache(binary_tx_hash, index)
      txout = self.output_for_outpoint(binary_tx_hash, index)
      txout.instance_variable_get(:@cached_model) rescue nil
    end

    # Returns true if every outpoint is available for spending
    # Each outpoint is [binary_tx_hash, out_index]
    def all_outpoints_are_available(spending_tx_hash, outpoints, memory_pool=nil)
      # See if we can answer this without any DB queries.
      quick_result = @output_cache.all_outpoints_are_unspent(outpoints)
      if quick_result
        # The below is noisy even for debug.
        #logger.debug{ "All outputs are available" }
        return true
      end

      # Not very efficient for now.
      # Hopefully, when we plug an in-memory UTXO cache in front of this it won't matter.
      outpoints.each do |txhash, i|
        # Check the cache.
        cached_result = @output_cache.outpoint_is_spent(txhash, i)
        if cached_result == true
          logger.debug{ "Output is already spent according to cached value." }
          return false
        end

        # Already checked it.
        next if cached_result == false

        # Cache miss, check the current block or DB
        hash = Toshi::Utils.bin_to_hex_hash(txhash)

        # Spent in current block?
        if txout_spent_in_current_block(hash, i) == true
          logger.debug{ "Output is already spent inside the current block" }
          return false
        end

        # Are the spender and output in the current block and does it try to spend a future output?
        if tx_in_current_block(spending_tx_hash) && txout_in_current_block(hash, i)
          spending_tx_position = tx_position_in_current_block(spending_tx_hash)
          outpoint_tx_position = tx_position_in_current_block(hash)
          if spending_tx_position <= outpoint_tx_position
            logger.debug{ "Output is in the future" }
            return false
          end
        end

        # Does it exist outside of the current block?
        output = self.output_from_model_cache(txhash, i)
        if !output
          if !memory_pool
            logger.debug{ "Output doesn't exist" }
            return false
          else
            # check the memory pool too
            if !memory_pool.is_output_available?(hash, i)
              logger.debug{ "Output is not available in memory pool nor UTXO set" }
              return false
            end
          end
          next
        end

        # Is it spendable?
        if !output.is_spendable? && (!memory_pool || !memory_pool.is_output_available?(hash, i))
          logger.debug{ "Output isn't spendable" }
          return false
        end
      end

      # All outpoints exist and are spendable.
      true
    end

    def load_output_cache2(row)
      txout = Bitcoin::Protocol::TxOut.new(row[:fix_amount].to_i, row[:script])
      output = Output.new
      output.id = row[:fix_id]
      output.amount = row[:fix_amount]
      output.hsh = row[:fix_hsh]
      output.position = row[:fix_pos]
      txout.instance_variable_set(:@cached_model, output)
      binary_hash = Toshi::Utils.hex_to_bin_hash(output.hsh)
      @output_cache.set_output_for_outpoint(binary_hash, output.position, txout)
    end

    # Helper method.
    def load_output_cache_from_query(query)
      Toshi::Models::Output.where(query).each{|output|
        # cache the results
        txout = Bitcoin::Protocol::TxOut.new(output.amount, output.script)
        txout.instance_variable_set(:@cached_model, output)
        binary_hash = Toshi::Utils.hex_to_bin_hash(output.hsh)
        @output_cache.set_output_for_outpoint(binary_hash, output.position, txout)
      }
    end

    # Bulk load relevant outputs into cache.
    # This is ugly but effective.
    def load_output_cache(txs)
      query = ''
      tx_seen = {}
      txs.each{|tx|
        if query.bytesize > (1024*1024*512)
          # Postgres' max stack depth is 2MB by default.
          # Matt's b39 would otherwise crash us here.
          load_output_cache_from_query(query)
          query = ''
        end
        # Fetch immediate outputs for this tx.
        query += (query.empty? ? '' : ' OR ') + "(hsh = '#{tx.hash}')"
        tx_seen[tx.hash] = true
        tx.in.each{|txin|
          # Fetch all spent prev outs too.
          next if txin.coinbase?
          next if tx_seen[txin.previous_output]
          if query.bytesize > (1024*1024*512)
            load_output_cache_from_query(query)
            query = ' '
          else
            query += ' OR '
          end
          query += "(hsh = '#{txin.previous_output}' AND position = #{txin.prev_out_index})"
        }
      }
      load_output_cache_from_query(query) if !query.empty?
    end

    # Returns TxOut object for the given outpoint.
    def output_for_outpoint(binary_tx_hash, out_index, for_test=false)
      # Try the cache.
      if txout = @output_cache.output_for_outpoint(binary_tx_hash, out_index)
        return txout
      end

      txhash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)

      # Try to find in DB.
      # FIXME: This is only needed to support tests calling are_inputs_standard? directly.
      if for_test && out = Toshi::Models::Output.where(hsh: txhash, position: out_index).first
        txout = Bitcoin::Protocol::TxOut.new(out.amount, out.script)
        if txout
          # cache the result
          txout.instance_variable_set(:@cached_model, out)
          @output_cache.set_output_for_outpoint(binary_tx_hash, out_index, txout)
        end
        return txout
      end

      # Try to find in current block
      txout = txout_in_current_block(txhash, out_index)
      if txout
        # cache the result
        @output_cache.set_output_for_outpoint(binary_tx_hash, out_index, txout)
      end
      return txout
    end

    # Returns true if the transaction is a coinbase
    def is_tx_coinbase(binary_tx_hash)
      quick_result = @output_cache.is_tx_coinbase(binary_tx_hash)
      if quick_result != nil
        return quick_result
      end

      hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)

      result = if dbtx = Toshi::Models::RawTransaction.where(hsh: hash).first
                 dbtx.bitcoin_tx.is_coinbase?
               elsif tx = tx_in_current_block(hash)
                 tx.is_coinbase?
               else
                 false
               end

      @output_cache.set_tx_coinbase(binary_tx_hash, result)
      return result
    end

    # Returns the height of the transaction (height of the block in which it is included)
    def height_for_tx(binary_tx_hash)
      hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)
      dbtx = Toshi::Models::Transaction.where(hsh: hash).first
      if !dbtx
        if tx = tx_in_current_block(hash)
          return 1 + self.height_for_block(@current_block.prev_block_hex)
        end
        return 0xffffffff
      end
      blk = dbtx.block
      return 0xffffffff if !blk
      blk.height
    end

    # move a coinbase tx to the block pool on disconnect
    def move_coinbase_tx_to_block_pool(tx_hash)
      Toshi::Models::Transaction.where(hsh: tx_hash).update({pool: Toshi::Models::Transaction::BLOCK_POOL})
    end

    # Orphan blocks

    # Saves orphan block for later ressurection when its non-orphan ancestors appear.
    # FIXME: probably we can drop the height support entirely because we need to recalculate it anyway when including in the chain.
    # Returns true if saved succesfully, false otherwise.
    def save_orphan_block(block, height = 0)
      !!Toshi::Models::Block.create_from_block(block, height, Toshi::Models::Block::ORPHAN_BRANCH, @output_cache)
      @output_cache.flush
    end

    # Returns enumerator of orphan blocks with a given parent hash
    def orphan_blocks_with_parent(hash)
      # For now, return simply an array.
      orphans = []
      Toshi::Models::Block.where(prev_block: hash, branch: Toshi::Models::Block::ORPHAN_BRANCH).each do |stored_orphan|
        orphans << self.raw_block_for_hash(stored_orphan.hsh)
      end
      orphans
    end

    # Removes orphan transaction if it ends up failing validation (for reasons other than missing inputs)
    def remove_orphan_tx(hash)
      t = Toshi::Models::Transaction.where(hsh: hash).first
      if t
        t.destroy
      end
    end

    # Used to prevent recursive calls to the index.
    # If we are asking index and it falls back to our storage, we should not attempt to call index again.
    # data_from_index = guard_block_index_access { @block_index.do_something }
    def guard_block_index_access(nil_value = nil, &block)
      if @prevent_index_access
        return nil_value
      end
      begin
        @prevent_index_access = true
        yield
      ensure
        @prevent_index_access = false
      end
    end
  end
end
