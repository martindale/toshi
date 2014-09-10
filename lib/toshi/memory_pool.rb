module Toshi
  # This class functions similar to bitcoind's CTxMemPool and uses Sequel/PostgreSQL for storage.
  class MemoryPool

    def initialize(output_cache)
      @output_cache = output_cache
    end

    # Does this tx exist in our view of the memory pool?
    def exists?(binary_tx_hash)
      hex_hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)
      tx = Toshi::Models::UnconfirmedTransaction.from_hsh(hex_hash)
      return false if tx && !tx.in_memory_pool?
      tx != nil
    end

    # Are we currently aware of this tx on the main branch or memory pool?
    def exists_including_main_branch?(binary_tx_hash)
      return true if exists?(binary_tx_hash)
      hex_hash = Toshi::Utils.bin_to_hex_hash(binary_tx_hash)
      tx = Toshi::Models::Transaction.from_hsh(hex_hash)
      return tx != nil && tx.in_view?
    end

    # Does the unspent output exist in the memory pool?
    def is_output_available?(tx_hash, position)
      output = Toshi::Models::UnconfirmedOutput.where(hsh: tx_hash, position: position).first
      return false if !output || !output.transaction.in_memory_pool?
      !output.spent
    end

    # Are any of the outputs spent by another tx in our view of the memory pool?
    def any_inputs_spent?(tx)
      tx.inputs.each{|txin|
        hash, i = txin.previous_output, txin.prev_out_index
        if input = Toshi::Models::UnconfirmedInput.where(prev_out: hash, index: i).first
          return true if !input.transaction.is_orphan?
        end
      }
      false
    end

    # Add the tx to the memory pool w/o validation (done by the processor)
    def add_unchecked(tx, on_disconnect=false)
      if on_disconnect
        # we may be disconnecting a blockchain tx so handle that like so
        Toshi::Models::Transaction.where(hsh: tx.hash)
          .update(pool: Toshi::Models::Transaction::BLOCK_POOL)
      end

      t = Toshi::Models::UnconfirmedTransaction.from_hsh(tx.hash)
      if t
        raise "BUG: should only be true for orphan transactions" if !t.is_orphan?
        t.update(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL)
      else
        t = Toshi::Models::UnconfirmedTransaction.create_from_tx(tx)
      end
      t.mark_spent_outputs
      t.update_unconfirmed_ledger_for_inputs(tx, @output_cache)
      t
    end

    # Track orphan txs in the hope that their parent(s) show up
    # Isn't really part of CTxMemPool but this seems like the logical place for this method.
    # See AddOrphanTx in bitcoind.
    def add_orphan_tx(tx)
      return false if Toshi::Models::UnconfirmedTransaction.from_hsh(tx.hash)

      # TODO: bitcoind limits the # of orhpans it will track.
      # we should consider doing the same except that bitcoind
      # performs random eviction and LRU logic makes more sense.
      # may be worth submitting a patch to bitcoind as well.

      # "Ignore big transactions, to avoid a
      # send-big-orphans memory exhaustion attack. If a peer has a legitimate
      # large transaction with a missing parent then we assume
      # it will rebroadcast it later, after the parent transaction(s)
      # have been mined or received.
      # 10,000 orphans, each of which is at most 5,000 bytes big is
      # at most 500 megabytes of orphans:" - bitcoind
      if (tx.payload || tx.to_payload).bytesize > 5000
        return false
      end

      # create the tx in the orphan pool
      Toshi::Models::UnconfirmedTransaction
        .create_from_tx(tx, Toshi::Models::UnconfirmedTransaction::ORPHAN_POOL)

      true
    end

    # Get a set of orphan txs given the hash of a potential input tx
    def get_orphan_txs_by_prev_hash(tx_hash)
      orphan_txs = []
      Toshi::Models::UnconfirmedInput.where(prev_out: tx_hash).each{|input|
        transaction = input.transaction
        if transaction.is_orphan?
          orphan_txs << transaction.bitcoin_tx
        end
      }
      orphan_txs
    end

    # Remove a tx from the memory pool
    # CTxMemPool::remove has a 'fRecursive' flag but whenever we use this it is always true.
    # we're really only using this to move mempool txs to the conflicted pool as we move things to
    # the tip pool via remove_for_block.
    #
    def remove(tx)
      tx.outputs.each_with_index{|txout,i|
        # recursively remove conflicts
        Toshi::Models::UnconfirmedInput.where(prev_out: tx.hash, index: i).each{|input|
          self.remove(input.transaction.bitcoin_tx)
        }
      }

      # mark the original tx as conflicted
      Toshi::Models::UnconfirmedTransaction.where(hsh: tx.hash)
        .update(pool: Toshi::Models::UnconfirmedTransaction::CONFLICT_POOL)

      # this might be a disconnected blockchain transaction
      Toshi::Models::Transaction.where(hsh: tx.hash)
        .update(pool: Toshi::Models::Transaction::CONFLICT_POOL)
    end

    # Remove transactions which depend on inputs of tx
    def remove_conflicts(tx)
      tx.inputs.each{|txin|
        next if txin.coinbase?
        # look for any spending inputs not tied to this immediate tx --
        # if we find one we should mark it a conflict.
        Toshi::Models::UnconfirmedInput.from_txin(txin).each{|input|
          next if input.hsh == tx.hash
          # remove it and any dependents
          self.remove(input.transaction.bitcoin_tx)
        }
      }
    end

    # Remove all txs in the block from the memory pool.
    def remove_for_block(block)
      tx_hashes = []

      block.tx.each{|tx|
        tx_hashes << tx.hash
        # remove any now conflicted txs from the memory pool --
        # these are txs which spend outputs spent by txs in this new block. why would this happen?
        # maybe a tx in the block wasn't relayed to us but an associated double-spend was.
        self.remove_conflicts(tx)
      }

      # TODO: should probably transfer timestamps and other information
      Toshi::Models::UnconfirmedTransaction.where(hsh: tx_hashes).destroy
      Toshi::Models::UnconfirmedRawTransaction.where(hsh: tx_hashes).delete

      # make sure the transactions are on the tip pool (if they previously existed.)
      Toshi::Models::Transaction.where(hsh: tx_hashes)
        .update(pool: Toshi::Models::Transaction::TIP_POOL)

      # handle the case of missing inputs for transactions in orphan blocks
      if Toshi::Models::Block.orphan_branch.where(hsh: block.hash).any?
        Toshi::Models::Transaction.update_address_ledger_for_missing_inputs(tx_hashes, @output_cache)
      end
    end

    # Create a TxOut given a TxIn.
    def output_for_outpoint(txin)
      unconfirmed_output = Toshi::Models::UnconfirmedOutput.prevout(txin)
      Bitcoin::Protocol::TxOut.new(unconfirmed_output.amount, unconfirmed_output.script) rescue nil
    end
  end
end
