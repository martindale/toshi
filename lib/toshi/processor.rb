module Toshi
  class Processor
    include Logging

    # Instance of BlockchainStorage that provides abstract API to store and retrieve blocks and transactions.
    attr_accessor :storage

    # For testing purposes: if true, skips checking actual proof of work in accept_block().
    # Default is false.
    attr_accessor :debug_skip_proof_of_work_check

    # If checkpoints are enabled, normally scripts before the checkpoint are not evaluated.
    # If you set it to true, all scripts will be evaluated (useful for testing purposes).
    # Default is false.
    attr_accessor :execute_all_scripts

    # If set to true, checkpoints are not used to protect against DoS and make verification faster.
    # Default is false.
    attr_accessor :checkpoints_disabled

    # If set to true, will allow accepting and relaying non-standard transactions on mainnet.
    # Testnet always allows non-standard transactions.
    # Default is false.
    attr_accessor :allow_nonstandard_tx_on_mainnet

    # If true, prints out details of validation failures
    attr_accessor :verbose_logging

    # Message queue interface
    attr_accessor :mq

    # Encapsulated all interesting info about a validation error to debug or punish the peer for DoS attempt.
    # Aka CValidationState in bitcoind.
    class ValidationState
      attr_reader :status, :error_message, :reason, :message, :terminate
      def initialize
      end
      def DoS(status, error_message, reason, msg, terminate=false)
        @status, @error_message, @reason, @message, @terminate = status, error_message, reason, msg, terminate
      end
    end

    # Validation error exceptions.
    # FIXME: we should probably use only ValidationState
    # to keep track of errors; and use return true/false to report success/failures.
    class ValidationError < StandardError
    end

    class BlockValidationError < ValidationError
    end

    class TxValidationError < ValidationError
    end

    class TxMissingInputsError < ValidationError
    end

    def initialize
      @output_cache = Toshi::OutputsCache.new

      @storage = Toshi::BlockchainStorage.new(@output_cache)
      @mempool = Toshi::MemoryPool.new(@output_cache)

      @trace_execution_steps_counter = 0
      @measurements = {}

      @mq = RedisMQ::Channel.new(:worker)

      if Bitcoin.network_name == :testnet3
        @debug_skip_proof_of_work_check = true
      end
    end

    def measure_method(method_name, start_time)
      return
      delta = Time.now.to_f - start_time.to_f
      current = (@measurements[method_name] ||= 0.0)
      new_value = (current*200 + delta)/(200.0 + 1.0)
      @measurements[method_name] = new_value
      puts "#{method_name.to_s.ljust(16)}  #{new_value} sec avg"
    end

    # This is the entry point to accepting unconfirmed transactions.
    def process_transaction(tx, raise_errors=false)
      @output_cache.flush
      accepted, missing_inputs_exception = false, nil

      @storage.transaction({auto_savepoint: true}) do
        begin
          accepted = self.accept_to_memory_pool(tx, false, raise_errors)
        rescue TxMissingInputsError => missing_inputs_exception
          # we don't want these to cause us to abort the db transaction
          @mempool.add_orphan_tx(tx)
        end
      end

      if accepted
        # Recursively process any orphan transactions that depended on this one
        relay_transaction_to_peers(tx)
        work_queue = [ tx.hash ]
        i = 0
        while i < work_queue.length do
          @mempool.get_orphan_txs_by_prev_hash(work_queue[i]).each do |orphan_tx|
            orphan_accepted = false
            @storage.transaction do
              begin
                orphan_accepted = self.accept_to_memory_pool(orphan_tx, false, false)
              rescue TxMissingInputsError
                # don't care about orphans still being orphans.
              rescue ValidationError => ex
                logger.warn{ "orphan tx #{orphan_tx.hash} failed validation: #{ex.message}" }
                @storage.remove_orphan_tx(orphan_tx.hash)
              end
              if orphan_accepted
                # orphan is no longer an orphan, see if it's a parent
                work_queue << orphan_tx.hash
                relay_transaction_to_peers(orphan_tx)
              end
            end
          end
          i += 1
        end
      end

      @output_cache.flush
      raise missing_inputs_exception if missing_inputs_exception && raise_errors

      return accepted
    rescue ValidationError, TxValidationError => e
      raise if raise_errors
      accepted
    end

    # FIXME: bitcoind won't relay inventory to peers that are known to already have it.
    def relay_transaction_to_peers(tx)
      @mq.workers_push_all({ 'msg' => 'relay_tx', 'hash' => tx.hash })
    end

    # FIXME: bitcoind won't relay inventory to peers that are known to already have it.
    def relay_block_to_peers(block)
      @mq.workers_push_all({ 'msg' => 'relay_block', 'hash' => block.hash })
    end

    # Returns true if transaction is valid if included in the next block.
    # See bool AcceptToMemoryPool() in bitcoind.
    def accept_to_memory_pool(tx, expect_tip=false, raise_errors=true, on_disconnect=false)
      start_time = Time.now
      state = ValidationState.new

      logger.debug{ "tx: #{tx.hash} start processing" }

      # Context-free verification of the transaction.
      if !self.check_transaction(tx, state)
        raise TxValidationError, "AcceptToMemoryPool() : check_transaction failed"
        return false
      end

      # Coinbase is only valid in a block, not as a loose transaction
      if tx.is_coinbase?
        # DoS 100
        raise TxValidationError, "AcceptToMemoryPool() : coinbase as individual tx"
        return false
      end

      # Rather not work on nonstandard transactions.
      if require_standard?
        is_standard, reason = self.is_standard_tx?(tx)
        if !is_standard
          raise TxValidationError, "AcceptToMemoryPool() : nonstandard transaction: #{reason}"
          return false
        end
      end

      # Is it already in the memory pool?
      if @mempool.exists?(tx.binary_hash)
        raise TxValidationError, "AcceptToMemoryPool() : already in the memory pool"
        return false
      end

      # Check for conflicts with in-memory transactions
      if @mempool.any_inputs_spent?(tx)
        raise TxValidationError, "AcceptToMemoryPool() : already spent in the memory pool"
        return false
      end

      # Check to see if we have the tx on the main branch or the memory pool already.
      if !expect_tip && @mempool.exists_including_main_branch?(tx.binary_hash)
        raise TxValidationError, "AcceptToMemoryPool() : transaction already seen"
        return false
      end

      # Do all inputs exist?
      # Note that this does not check for the presence of actual outputs (see the next check for that),
      # only helps filling in pfMissingInputs (to determine missing vs spent).
      tx.inputs.each do |txin|
        if !@mempool.exists_including_main_branch?(txin.prev_out)
          # this tx is an orphan -- missing parent input.
          raise TxMissingInputsError, "AcceptToMemoryPool() : transaction missing inputs"
          return false
        end
      end

      # Bulk load the output cache from the db with the relevant outputs.
      @storage.load_output_cache([tx]) if !on_disconnect

      # Are the actual inputs available?
      if !self.verify_inputs_are_available(tx, include_memory_pool=true)
        raise TxValidationError, "AcceptToMemoryPool() : inputs already spent"
        # TODO:
        #     return state.Invalid(error("AcceptToMemoryPool() : inputs already spent"),
        #                          REJECT_DUPLICATE, "bad-txns-inputs-spent");
        return false
      end

      # Check for non-standard pay-to-script-hash in inputs

      if require_standard?
        if !are_inputs_standard?(tx)
          raise TxValidationError, "AcceptToMemoryPool() : nonstandard transaction input"
          return false
        end
      end

      # Note: if you modify this code to accept non-standard transactions, then
      # you should add code here to check that the transaction does a
      # reasonable number of ECDSA signature verifications.

      # TODO: potentially check fees.

      # Check against previous transactions.
      # This is done last to help prevent CPU exhaustion denial-of-service attacks.

      last_block = @storage.block_header_for_hash(@storage.mainchain_tip_hash)
      if !check_inputs(last_block, tx, state, check_scripts=true, strict_p2sh=true, include_memory_pool=true)
        raise TxValidationError, "AcceptToMemoryPool() : ConnectInputs failed #{tx.hash}"
        return false
      end

      logger.debug{ "tx #{tx.hash} accepted to memory pool" }
      @mempool.add_unchecked(tx, on_disconnect)

      return true

    rescue TxValidationError => ex
      logger.warn{ "tx rejected: #{ex.message}" } if !raise_errors
      raise if raise_errors
      return false
    end

    # This is the entry point to validation of the block.
    # It does as many checks as possible to allow orphan blocks, attempts to accept_block()
    # and recursively processes pending orphan blocks if possible.
    # Argument <block> is an instance of Bitcoin::Protocol::Block.
    # Uses check_block and check_transaction for individual storage-indifferent validations.
    # Uses accept_block as the next step in validation process.
    # See ProcessBlock() in bitcoind.
    def process_block(block, raise_errors=false, current_time=nil)
      @output_cache.flush
      @storage.current_block = nil
      result = false
      accepted_parents = []
      begin
        # Wrap validation process in a atomic and isolated transaction.
        # This is required so we can disconnect and connect blocks and safely fail validating them in the middle.
        @storage.transaction do
          Toshi.db.after_rollback {
            logger.debug {"db txn rolled back for block: #{block.hash}"}
            @output_cache.flush
            @storage.remove_block_header(block)
          }
          result = process_block_internal(block, raise_errors, current_time)
          if result && @storage.is_block_valid?(block.hash)
            # this block is a valid parent
            accepted_parents = [ block.hash ]
          end
          if !result
            logger.debug {"process_block_internal false for block: #{block.hash}"}
            raise Sequel::Rollback
          end
        end
      rescue ValidationError
        @storage.current_block = nil
        raise if raise_errors
        return result
      end

      # consume the array of parents from beginning to the end.
      while accepted_parent_hash = accepted_parents.shift
        # Try to accept the orphan and remove it from the database.
        @storage.orphan_blocks_with_parent(accepted_parent_hash).each do |orphan|
          accepted_parents += accept_orphan(orphan)
        end
      end # end checking orphans recursively.

      @storage.current_block = nil
      result
    end

    # Actual implementation of ProcessBlock.
    def process_block_internal(block, raise_errors=false, current_time=nil)
      @current_time = current_time
      @processing_start_time = Time.now
      logger.debug{ "ProcessBlock(): starting %s" % [block.hash] }

      # Check for duplicate.
      # Bitcoind checks all blocks: mainchain, sidechain, orphans.
      if @storage.is_block_processed?(block.hash)
        b = @storage.processed_block_for_hash(block.hash)
        logger.debug{ "ProcessBlock() : already have block %s" % [b.hash] }
        return true
      else
        # Store the raw block for later use.
        # This is not the same as AcceptBlock in bitcoind.
        # In fact, the raw block may already be there before processing because it was received from other nodes.
        @storage.store_raw_block(block)
      end

      # This will track the reasons of failure and DoS penalties.
      state = ValidationState.new

      # Preliminary checks
      if !check_block(block, state)
        return false
      end

      # Load the latest mainchain block
      mainchain_tip_hash = @storage.mainchain_tip_hash

      # Checkpoints check.
      # Since we store around orphan blocks, we need at least to check that POW is good relative to the latest checkpoint.
      # - Find the last checkpoint hash *before this block*
      # - Find the block for this hash.
      # - if this block's previous hash is not the current tip or nil, verify against checkpoints:
      # - timestamp should be >= the checkpoint time
      # - minimal possible work since checkpoint should be satisfied
      checkpoint_hash = self.latest_checkpoint_hash

      # Only check if this block is not built on top of the current tip.
      if !@checkpoints_disabled && checkpoint_hash && block.prev_block_hex != (mainchain_tip_hash || ("00"*32))
        checkpoint_block = @storage.processed_block_for_hash(checkpoint_hash)
        time_delta = block.time - checkpoint_block.time
        if time_delta < 0
          raise BlockValidationError, "ProcessBlock() : block with timestamp before last checkpoint"
        end

        base_work = Bitcoin.decode_compact_bits(checkpoint_block.bits).to_i(16)
        max_target = compute_min_work(base_work, time_delta)

        if block.decimaltarget > max_target
          raise BlockValidationError, "ProcessBlock() : block with too little proof-of-work"
        end
      end

      # If block is orphan (for which we don't have the parent yet), store it for later use and return true (if stored succesfully)
      # Bitcoind: "If we don't already have its previous block, shunt it off to holding area until we get it"

      prev_block_valid = @storage.is_block_valid?(block.prev_block_hex)
      if !prev_block_valid
        # If it's a genesis block, simply save it right away
        # In Bitcoind this is saved apriori, AFAIU.
        if block.hash == Bitcoin.network[:genesis_hash]
          log_raw_block_events(block.hash, "process_block => genesis (0)")
          return persist_block_on_main_branch(block, 0)
        end

        # It is an orphan block.
        # Note: Bitcoind saves it if there's a node to request missing blocks from.

        # FIXME: maybe we can drop height support from here as we'd have to update all heights anyway when processing the orphans.
        # If we have a parent (which is also orphan), increase the height relative to the parent.
        # Otherwise, use height 0.
        height = @storage.height_for_block(block.prev_block_hex)
        height = height ? (height + 1) : 0

        log_raw_block_events(block.hash, "process_block => orphan (#{height})")

        # Store orphan and return.
        return persist_orphan_block(block, height)
      end

      measure_method(:process_block, @processing_start_time)

      # Reorg happens inside if needed.
      if !self.accept_block(block, state)
        # Note: if accept_block raises exceptions, this exception will never be raised.
        raise BlockValidationError, "ProcessBlock() : AcceptBlock FAILED"
        return false
      end

      return true
    rescue ValidationError, BlockValidationError, TxValidationError => e
      log_raw_block_events(block.hash, e)
      msg = "process_block total time: #{(Time.now - @processing_start_time).to_f}"
      log_raw_block_events(block.hash, msg)
      raise if raise_errors
      return false
    end # process_block

    # processes orphan block within a nested transaction, returning that
    # orphan's hash if the block is accepted
    def accept_orphan orphan
      new_parent = []
      begin
        @storage.transaction do
          Toshi.db.after_rollback {
            @output_cache.flush
            @storage.remove_block_header(orphan)
            logger.debug{"db txn rolled back for orphan #{orphan.hash}"}
          }
          # Use a dummy ValidationState so someone can't setup nodes to counter-DoS based on orphan resolution
          # (that is, feeding people an invalid block based on LegitBlockX in order to get anyone relaying LegitBlockX banned)
          dummy_state = ValidationState.new
          log_raw_block_events(orphan.hash, "recursively processing orphan block")
          if self.accept_block(orphan, dummy_state)
            # Orphan is no longer an orphan and now becomes another parent to process.
            new_parent << orphan.hash
          else
            # rollback invalid orphan db transaction
            raise BlockValidationError, "accept_block failed for orphan block with unknown reason"
          end
        end
      rescue ValidationError, BlockValidationError, TxValidationError => e
        # Failed to accept_block because orphan is invalid. Move on with other orphans.
        log_raw_block_events(orphan.hash, "accept_block failed for orphan block: #{e.message()}")
        # Note that we're keeping the block in our db. This is strictly different from bitcoind's
        # handling of orphan blocks. We do so for archival purposes. We may re-think that at some point.
      end
      new_parent
    end

    # Returns false if block is invalid.
    # See CheckBlock() in bitcoind.
    def check_block(block, state, check_pow=true, check_merkle_root=true)
      # These are checks that are independent of context that can be verified before saving an orphan block.
      start_time = Time.now

      # Size limits
      if (block.tx.empty? || block.tx.size > Bitcoin::MAX_BLOCK_SIZE ||
          (block.payload || block.to_payload).bytesize > Bitcoin::MAX_BLOCK_SIZE)
        raise BlockValidationError, "CheckBlock() : size limits failed"
      end

      # Check proof of work matches claimed amount
      if check_pow && !check_proof_of_work(block)
        raise BlockValidationError, "CheckBlock() : proof of work failed"
      end

      # Check timestamp
      if block.time > (@current_time || (NodeTime.adjusted_time + 7200)) # 7200 == 2*60*60
        raise BlockValidationError, "CheckBlock() : block timestamp too far in the future"
      end

      # First transaction must be coinbase, the rest must not be
      if !block.tx.first.is_coinbase?
        raise BlockValidationError, "CheckBlock() : first tx is not coinbase"
      end

      # Other transactions must not be coinbases.
      if block.tx[1..-1].any?{|tx| tx.is_coinbase? }
        raise BlockValidationError, "CheckBlock() : more than one coinbase"
      end

      # Check individual transactions
      block.tx.each do |tx|
        if !check_transaction(tx, state)
          return false
        end
      end

      # Check for duplicate txids. This is caught by ConnectInputs(), but catching it earlier avoids a potential DoS attack:
      txids = block.tx.map{|tx| tx.hash }
      if txids.size != txids.uniq.size
        raise BlockValidationError, "CheckBlock() : duplicate transaction"
      end

      # Check sigops: there's a limit of signature operations per block.
      sigops = 0
      block.tx.each do |tx|
        sigops += tx.legacy_sigops_count
      end
      if sigops > Bitcoin::MAX_BLOCK_SIGOPS
        raise BlockValidationError, "CheckBlock() : out-of-bounds signature operations count"
      end

      # Check merkle root
      if check_merkle_root && !block.verify_mrkl_root
        raise BlockValidationError, "CheckBlock() : hashMerkleRoot mismatch"
      end

      msg = "CheckBlock processing time: #{(Time.now - start_time).to_f}"

      measure_method(:check_block, start_time)
      log_raw_block_events(block.hash, msg)
      true
    end

    # Checks individual transaction without reference to any other transactions or blocks.
    # See CheckTransaction() in bitcoind.
    def check_transaction(tx, state)
      # Basic checks that don't depend on any context
      if tx.inputs.empty?
        raise TxValidationError, "CheckTransaction() : vin empty"
        return false
      end

      if tx.outputs.empty?
        raise TxValidationError, "CheckTransaction() : vout empty"
        return false
      end

      # Size limits
      if (tx.payload || tx.to_payload).bytesize > Bitcoin::MAX_BLOCK_SIZE
        raise TxValidationError, "CheckTransaction() : size limits failed"
        return false
      end

      # Check for negative or overflow output values
      total_value_out = 0
      tx.outputs.each do |output|
        if output.value < 0
          raise TxValidationError, "CheckTransaction() : txout.nValue negative"
          return false
        end
        if output.value > Bitcoin.network[:max_money]
          raise TxValidationError, "CheckTransaction() : txout.nValue too high"
          return false
        end

        total_value_out += output.value
        if total_value_out > Bitcoin.network[:max_money]
          raise TxValidationError, "CheckTransaction() : txout total out of range"
          return false
        end
      end

      # Check for duplicate inputs
      inputs = tx.inputs.map{|input| [input.prev_out, input.prev_out_index] }
      if inputs.size != inputs.uniq.size
        raise TxValidationError, "CheckTransaction() : duplicate inputs"
        return false
      end

      if tx.is_coinbase?
        if !tx.inputs.first.script.bytesize.between?(2,100)
          raise TxValidationError, "CheckTransaction() : coinbase script size"
          return false
        end
      else
        if tx.inputs.any?{|input| input.prev_out == Bitcoin::Protocol::TxIn::NULL_HASH }
          raise TxValidationError, "CheckTransaction() : prevout is null"
          return false
        end
      end

      true
    end

    # Happens when the block attempts to extend the main chain or the side chain.
    # In Bitcoind, AcceptBlock() detects if reorganization happens (sidechain becomes the mainchain),
    # and reindexes available UTXOs. Scripts and signatures are checked only when
    # the block is added to the main chain. This is because their index only applies to the mainchain,
    # and does not allow search in the sidechains. So when reorg happens, blocks "undo" their effects on the index,
    # while new mainchain blocks "apply" their effects on the index.
    # See AcceptBlock() in bitcoind.
    def accept_block(block, state)
      start_time = Time.now

      # If it's a genesis block, it was already saved in process_block, nothing to do here.
      # (In fact, this condition should never happen here.)
      if block.hash == Bitcoin.network[:genesis_hash]
        return true
      end

      prev_block_header = @storage.block_header_for_hash(block.prev_block_hex)

      # Compute new height as height of the previous block + 1.
      new_height = @storage.height_for_block_header(prev_block_header) + 1

      # Check for duplicates once again, like in Bitcoind (but not orphans as we may be processing orphan right now)
      if @storage.is_block_valid?(block.hash)
        raise BlockValidationError, "AcceptBlock() : block already validated"
        return false
      end

      # Check proof of work

      if !@debug_skip_proof_of_work_check
        next_bits = self.block_next_bits_required(block)
        if next_bits != block.bits
          if @verbose_logging
            puts "block #{block.hash} bits: #{block.bits} (required next bits: #{next_bits})"
            trace_execution_steps do
              self.block_next_bits_required(block)
            end
          end
          raise BlockValidationError, "AcceptBlock() : incorrect proof of work"
        end
      end

      # Check timestamp against previous blocks
      if block.time <= self.block_median_timestamp_for_block_header(prev_block_header)
        raise BlockValidationError, "AcceptBlock() : block's timestamp is too early"
      end

      # Check that all transactions are finalized
      block.tx.each do |tx|
        if !self.tx_is_final?(tx, new_height, block.time)
          raise BlockValidationError, "AcceptBlock() : contains a non-final transaction"
        end
      end

      # Check that the block chain matches the known block chain up to a checkpoint.
      # If this block's height matches the height of a known checkpoint, make sure it's the same block.
      # See Checkpoints::CheckBlock() in bitcoind.
      checkpoint_hash = !@checkpoints_disabled && new_height && Bitcoin.network[:checkpoints][new_height]
      if checkpoint_hash && block.hash != checkpoint_hash
        raise BlockValidationError, "AcceptBlock() : rejected by checkpoint lock-in at %d" % [new_height]
      end

      # Don't accept any forks from the main chain prior to last checkpoint
      checkpoint_hash = self.latest_checkpoint_hash
      if !@checkpoints_disabled && checkpoint_hash && new_height < self.height_of_checkpoint(checkpoint_hash)
        raise BlockValidationError, "AcceptBlock() : forked chain older than last checkpoint (height %d)" % [new_height]
      end

      # BIP34 introduced blocks version 2 that contain their height in the coinbase script.
      # https://github.com/bitcoin/bips/blob/master/bip-0034.mediawiki

      # BIP34 Part 1. Reject block.nVersion=1 blocks when 95% (75% on testnet) of the network has upgraded:
      if block.ver < 2
        if ((!is_testnet? && verify_block_version_super_majority(2, prev_block_header, 950, 1000)) ||
            (is_testnet? && verify_block_version_super_majority(2, prev_block_header, 75,  100)))
          raise BlockValidationError, "AcceptBlock() : rejected nVersion=1 block #{block.hash}"
        end
      end

      # BIP34 Part 2. Enforce block.nVersion=2 rule that the coinbase starts with the serialized block height
      if block.ver >= 2
        # if 750 of the last 1,000 blocks are version 2 or greater (51/100 if testnet)
        if ((!is_testnet? && verify_block_version_super_majority(2, prev_block_header, 750, 1000)) ||
            (is_testnet? && verify_block_version_super_majority(2, prev_block_header, 51,  100)))

          if block.bip34_block_height != new_height
            # DoS 100
            raise BlockValidationError, "AcceptBlock() : block height mismatch in coinbase"
          end
        end
      end

      # Here bitcoind does three things:
      # 1. WriteBlockToDisk - this is already taken care of by RawBlock
      # 2. AddToBlockIndex - here mainchain is determined and the rest of validations is performed.
      # 3. Relay inventory
      # In our case, we need to compute which is the main chain
      # and disconnect/connect blocks while validating individual transactions.

      measure_method(:accept_block, start_time)
      log_raw_block_events(block.hash, "accept_block processing time: #{(Time.now - start_time).to_f}")

      result = self.add_block(block, state)

      # Relay inventory: the IO worker will enforce that we don't send old blocks.
      relay_block_to_peers(block) if result

      return result
    end

    # Saves block and figures out the current main chain.
    # For those blocks that get connected to the main chain, extra transaction verification is performed.
    # Equivalent to AddToBlockIndex() in bitcoind.
    def add_block(block, state)
      start_time = Time.now

      mainchain_tip_hash = @storage.mainchain_tip_hash
      thischain_tip_hash = block.prev_block_hex

      mainchain_tip = @storage.block_header_for_hash(mainchain_tip_hash)
      thischain_tip = @storage.block_header_for_hash(thischain_tip_hash)

      # Compare the total work of two chains: current mainchain and the new chain with the given block.
      mainchain_work = @storage.total_work_up_to_block_header(mainchain_tip)
      thischain_work = @storage.total_work_up_to_block_header(thischain_tip)
      this_block_work = block.block_work # Bitcoin::Protocol::Block#block_work computes work from block.bits.

      new_chain_work = (thischain_work + this_block_work)

      # If the new work does not exceed the main chain work, stash this block away in a "side branch".
      # No further validations will be performed.
      if new_chain_work <= mainchain_work
        # This can only possible on the sidechain, so we simply store the block without further validations.
        # Outputs will be validate when/if this block will become a part of the mainchain (see below).
        @storage.load_output_cache(block.tx)
        return persist_block_on_side_branch(block,
                                            @storage.height_for_block_header(thischain_tip) + 1,
                                            thischain_work)
      end

      # New work is greater. Find the common ancestor block to rebuild the chain from there.
      # Scan both chains up to the common (minimum) height.
      # Then scan from there simultaneously until we hit the same hash.

      mainchain_ancestor = mainchain_tip
      thischain_ancestor = thischain_tip

      block_hashes_to_disconnect = []
      block_hashes_to_connect = []

      # 1. Scan each chain until the common min_height
      min_height = [ @storage.height_for_block_header(mainchain_ancestor),
                     @storage.height_for_block_header(thischain_ancestor) ].min

      while @storage.height_for_block_header(mainchain_ancestor) > min_height
        block_hashes_to_disconnect << mainchain_ancestor.hash
        mainchain_ancestor = @storage.previous_block_header_for_block_header(mainchain_ancestor)
      end

      while @storage.height_for_block_header(thischain_ancestor) > min_height
        block_hashes_to_connect << thischain_ancestor.hash
        thischain_ancestor = @storage.previous_block_header_for_block_header(thischain_ancestor)
      end

      # 2. Scan both chains simultaneously until we get to the same common ancestor
      while !(thischain_ancestor == mainchain_ancestor)
        block_hashes_to_disconnect << mainchain_ancestor.hash
        block_hashes_to_connect    << thischain_ancestor.hash
        mainchain_ancestor = @storage.previous_block_header_for_block_header(mainchain_ancestor)
        thischain_ancestor = @storage.previous_block_header_for_block_header(thischain_ancestor)
      end

      # Finally we arrive at the common ancestor.
      # Now we need to attempt to disconnect old mainchain blocks and connect new thischain blocks.
      common_ancestor = mainchain_ancestor

      # 1. Disconnect the blocks on the mainchain to move them into the sidechain
      # We start from the latest hash and move on to the one right before the common ancestor.
      # Most of the time this array is empty, so no blocks are being disconnected.
      block_hashes_to_disconnect.each do |hash|
        b = @storage.valid_block_for_hash(hash)
        @storage.load_output_cache(b.tx)
        if !self.disconnect_block(b, state)
          return false
        end
      end

      # 2. Connect the blocks to form the new mainchain.
      # If any block is actually invalid (double-spends some outputs or has an invalid script),
      # this will fail and we would have to abort DB transaction to rollback all changes.
      block_hashes_to_connect.reverse.each do |hash|
        b = @storage.valid_block_for_hash(hash)
        @storage.load_output_cache(b.tx)
        if !self.connect_block(b, state)
          return false
        end
      end

      measure_method(:add_block, start_time)
      log_raw_block_events(block.hash, "add_block processing time: #{(Time.now - start_time).to_f}")

      # Connect this new block too.
      @storage.load_output_cache(block.tx)
      if !self.connect_block(block, state)
        return false
      end

      return true
    end # add_block

    # Undoes effects of the block on unspent transaction outputs.
    # See DisconnectBlock() in bitcoind.
    def disconnect_block(block, state)
      start_time = Time.now
      # Disconnect transactions in reverse order
      # (because transactions can spend themselves inside the same block)
      block.transactions.reverse.each do |tx|
        if !self.disconnect_inputs(tx, state)
          return false
        end
      end

      # Update the outputs in the database in bulk
      @storage.update_outputs_on_disconnect_block(block)

      block.transactions.each do |tx|
        # add the txs back to the memory pool
        if !tx.is_coinbase?
          if !self.accept_to_memory_pool(tx, true, raise_errors=false, on_disconnect=true)
            @mempool.remove(tx)
          end
        else
          # in bitcoind the old coinbases would be out of view, we still have them in
          # view since we keep everything so we need to move these to the block pool
          # otherwise they'd be left in the tip pool.
          @storage.move_coinbase_tx_to_block_pool(tx.hash)
        end
      end

      log_raw_block_events(block.hash, "disconnect_block processing time: #{(Time.now - start_time).to_f}")

      # Store this block as a sidechain block
      # Note: if we want to improve locking, this should stash this block away in a processor's queue and update
      # the current tip.
      return persist_block_on_side_branch(block, @storage.height_for_block(block.hash))
    end

    def disconnect_inputs(tx, state)
      if !tx.is_coinbase?
        # unmark the spent outputs
        tx.inputs.each do |txin|
          @storage.mark_output_as_unspent(txin.prev_out, txin.prev_out_index)
        end
      end

      # remove outputs
      tx.outputs.each_with_index do |txout, i|
        @storage.mark_output_as_not_available(tx.binary_hash, i)
      end

      return true
    end

    # Connects inputs with existing unspent outputs.
    # Returns false if block contains double spends or invalid scripts.
    # See ConnectBlock() in bitcoind.
    def connect_block(block, state)
      start_time = Time.now

      # Check it again in case a previous version let a bad block in
      if !self.check_block(block, state)
        return false
      end

      # Special case for the genesis block, skipping connection of its transactions
      # (its coinbase is unspendable because since the beginning it wasn't included in UTXO index)
      if block.hash == Bitcoin.network[:genesis_hash]
        # We do not store the block as it is already stored early in the processing.
        return true
      end

      # Let the storage know about the current block (as it can spent its own transactions)
      # This way, when we request outputs, we'll be able to get them from the current block.
      # This block is reset when transaction completes/rollbacks or when we process another block.
      @storage.current_block = block

      # This block may not be stored in the chain yet, so refer to its parent to get the height and add 1.
      height = 1 + @storage.height_for_block(block.prev_block_hex)

      # Skip scripts evaluation before the last checkpoint to speed up download process.
      #
      check_scripts = (@execute_all_scripts || @checkpoints_disabled || height >= self.max_checkpoint_height)

      # Enforce BIP30 - disallow overwriting transactions that were not completely spent yet.
      if !self.enforce_BIP30(block, height, state)
        return false
      end

      # BIP16 (P2SH scripts) didn't become active until Apr 1 2012.
      bip16_switch_time = 1333238400
      strict_p2sh = (block.time >= bip16_switch_time)

      # TODO: implement the flags.
      #unsigned int flags = SCRIPT_VERIFY_NOCACHE |
      #                     (fStrictPayToScriptHash ? SCRIPT_VERIFY_P2SH : SCRIPT_VERIFY_NONE);

      # Will count total fees (to verify block balance)
      fees = 0

      # Will count signature operations to prevent DoS.
      sigops = 0

      block.tx.each do |tx|
        # This is already counted in check_block(), but we have to add P2SH signature counts to it as well.
        # (And P2SH sigops can't be discovered until we actually attempt to connect unspent outputs.)
        sigops += tx.legacy_sigops_count

        if sigops > Bitcoin::MAX_BLOCK_SIGOPS
          # DoS 100
          raise BlockValidationError, "ConnectBlock() : too many sigops"
          return false
        end

        if !tx.is_coinbase?
          # Check if there are unspent outputs for this tx's inputs
          # aka view.HaveInputs() - but with only a view of pcoinsTip.
          if !self.verify_inputs_are_available(tx)
            raise BlockValidationError, "ConnectBlock() : inputs missing/spent"
            return false
          end

          if strict_p2sh
            # Add in sigops done by pay-to-script-hash inputs;
            # this is to prevent a "rogue miner" from creating
            # an incredibly-expensive-to-validate block.

            sigops += self.p2sh_sigops_count(tx);

            if sigops > Bitcoin::MAX_BLOCK_SIGOPS
              # DoS 100
              raise BlockValidationError, "ConnectBlock() : too many sigops"
              return false
            end
          end

          # Compute fees:
          # nFees += view.GetValueIn(tx)-tx.GetValueOut();

          # Note: we don't validate that each transaction does not spend more than on its inputs.
          # The balances are checked only per-block, so it's possible for some transactions to have negative fees
          # (provided some other transactions in the block have positive fees to compensate for that).
          fees += tx_value_in(tx) - tx_value_out(tx)

          # Actually check scripts. See CheckInputs() in bitcoind.
          if !self.check_inputs(block, tx, state, check_scripts, strict_p2sh, include_memory_pool=false)
            return false
          end

        end # not a coinbase

        # UpdateCoins - mark inputs as spent and add new outputs as unspent.
        self.update_unspent_outputs(tx)

      end # each tx in block

      # Optimized method for marking outputs in the database in bulk
      @storage.update_outputs_on_connect_block(block)

      # mempool.removeForBlock() normally done in ConnectTip()
      @mempool.remove_for_block(block)

      # Verify that coinbase pays no more than fees + block reward.
      coinbase_out_value = tx_value_out(block.tx[0])
      max_value = Bitcoin.block_creation_reward(height) + fees
      if coinbase_out_value > max_value
        # DoS 100
        raise BlockValidationError, ("ConnectBlock() : coinbase pays too much (actual=%d vs limit=%d)" % [coinbase_out_value, max_value])
      end

      measure_method(:connect_block, start_time)
      log_raw_block_events(block.hash, "ConnectBlock processing time: #{(Time.now - start_time).to_f}")

      # Save the block on "main branch"
      self.persist_block_on_main_branch(block, height, @storage.total_work_up_to_block_hash(block.prev_block_hex))

      return true
    end

    # Returns true if tx does not attempt to overwrite another,
    # not fully spent transaction with the same hash.
    def enforce_BIP30(block, height, state)
      # Do not allow blocks that contain transactions which 'overwrite' older transactions,
      # unless those are already completely spent.
      # If such overwrites are allowed, coinbases and transactions depending upon those
      # can be duplicated to remove the ability to spend the first instance -- even after
      # being sent to another address.
      # See BIP30 and http://r6.ca/blog/20120206T005236Z.html for more information.
      # This logic is not necessary for memory pool transactions, as AcceptToMemoryPool
      # already refuses previously-known transaction ids entirely.
      # This rule was originally applied all blocks whose timestamp was after March 15, 2012, 0:00 UTC.
      # Now that the whole chain is irreversibly beyond that time it is applied to all blocks except the
      # two in the chain that violate it. This prevents exploiting the issue against nodes in their
      # initial block download.
      enforceBIP30 = !((height == 91842 &&
                        block.hash == "00000000000a4d0a398161ffc163c503763b1f4360639393e0e4c8e300e0caec") ||
                       (height == 91880 &&
                        block.hash == "00000000000743f190a18c5577a3c2d2a1f610ae9601ac046a38084ccb7cd721"))

      if enforceBIP30
        # Fail if has still spendable outputs for any of the hashes
        if @storage.has_previously_unspent_outputs_for_any_tx(block)
          raise BlockValidationError, "ConnectBlock() : tried to overwrite transaction (BIP30)"
          return false
        end
      end

      return true
    end

    # Well-known transactions for which we don't verify input scripts
    # because the existing script runner in bitcoin-ruby could not process them correctly.
    SKIP_TXS = [
    ]

    # Returns true if all inputs are valid.
    # block - current block - used to figure out time, height etc.
    # tx - transaction
    # state - validation state
    # check_scripts - flag; if false, script evaluation can be skipped.
    # strict_p2sh - flag; if false, P2SH scripts are not evaluated.
    # See CheckInputs() in bitcoind.
    def check_inputs(block, tx, state, check_scripts, strict_p2sh, include_memory_pool)
      return true if tx.is_coinbase?

      if !self.verify_inputs_are_available(tx, include_memory_pool)
        # This doesn't trigger the DoS code on purpose; if it did, it would make it easier
        # for an attacker to attempt to split the network.
        raise TxValidationError, "CheckInputs() : #{tx.hash} inputs unavailable"
        return false
      end

      # Get the height for the current block
      height = 1 + @storage.height_for_block(block.prev_block_hex)

      value_in = 0

      # Perform inexpensive checks on all inputs.
      tx.inputs.each do |txin|
        txout = @storage.output_for_outpoint(txin.prev_out, txin.prev_out_index)
        # TODO: This isn't the cleanest way to also look at the memory pool.
        if !txout && include_memory_pool
          txout = @mempool.output_for_outpoint(txin)
        end

        # If spending a coinbase, make sure it's mature enough.
        if @storage.is_tx_coinbase(txin.prev_out)
          output_height = @storage.height_for_tx(txin.prev_out)
          maturity = Bitcoin.network[:coinbase_maturity]
          depth = height - output_height
          if depth < maturity
            raise TxValidationError, "CheckInputs() : tried to spend coinbase at depth #{depth} < #{maturity}"
            return false
          end
        end

        # Check for negative or overflow input values
        value_in += txout.value

        if !valid_money_range(txout.value) || !valid_money_range(value_in)
          # DoS 100
          raise TxValidationError, "CheckInputs() : txin values out of range"
          return false
        end

      end # each input

      value_out = self.tx_value_out(tx)

      if value_in < value_out
        # DoS 100
        raise TxValidationError, "CheckInputs() : tx #{tx.hash} value in < value out"
        return false
      end

      # Tally transaction fees
      fee = (value_in - value_out)

      if !valid_money_range(fee)
        raise TxValidationError, "CheckInputs() : fees out of range"
        return false
      end

      # The first loop above does all the inexpensive checks.
      # Only if ALL inputs pass do we perform expensive ECDSA signature checks.
      # Helps prevent CPU exhaustion attacks.

      # Skip ECDSA signature verification when connecting blocks
      # before the last block chain checkpoint. This is safe because block merkle hashes are
      # still computed and checked, and any change will be caught at the next checkpoint.
      # This flag is set earlier, in connect_block method.
      #
      # # If it's a well-known transaction, skip script validation for it.
      if check_scripts && !SKIP_TXS.include?(tx.hash)
        # For each input, execute the script.
        tx.inputs.each_with_index do |txin, i|
          if !txin.coinbase?
            txout = @storage.output_for_outpoint(txin.prev_out, txin.prev_out_index)
            # TODO: This isn't the cleanest way to also look at the memory pool.
            if !txout && include_memory_pool
              txout = @mempool.output_for_outpoint(txin)
            end
            script_pubkey = txout.pk_script
            #puts "Script check: #{script_pubkey.inspect}"
            if !tx.verify_input_signature(i, script_pubkey, block.time)
              raise TxValidationError, "Script evaluation failed"
              false
            end
          end
        end # each input
      end # if check_scripts

      # Tx is valid, add some extra aggregate data for use in @storage
      self.cache_additional_tx_fields(tx, fee, value_in, value_out)

      return true
    end

    # cache these values for use when persisting to the db.
    def cache_additional_tx_fields(tx, fee, value_in, value_out)
      tx.additional_fields = {
        :fee             => fee,
        :total_in_value  => value_in,
        :total_out_value => value_out
      }
    end

    ############################################################################
    # Validation helpers

    # Checks if this transaction is standard.
    # See IsStandardTx() in bitcoind.
    def is_standard_tx?(tx)
      # check version
      if tx.ver > Toshi::CURRENT_TX_VERSION || tx.ver < 1
        return [ false, 'version' ]
      end

      # tx is final?
      return [ false, 'non-final' ] if !tx_is_final?(tx)

      # check the size
      if (tx.payload || tx.to_payload).bytesize >= Toshi::MAX_STANDARD_TX_SIZE
        return [ false, 'tx-size' ]
      end

      # check for standard input scripts
      tx.inputs.each{|txin|
        # check size
        return [ false, 'scriptsig-size' ] if txin.script_sig_length > 1650

        # scriptSigs should only push data
        return [ false, 'scriptsig-not-pushonly' ] if !script_is_push_only?(txin.script)

        # one known source of tx malleability is a non-canonical push
        # ie. using OP_PUSHDATA2 when you only need to push 40 bytes
        return [ false, 'scriptsig-non-canonical-push' ] if !script_pushes_are_canonical?(txin.script)
      }

      op_return_count = 0

      # check for standard output scripts
      tx.outputs.each{|txout|
        script = Bitcoin::Script.new(txout.pk_script)

        # TODO: not sure this is perfectly analogous to using Solver(). think more.
        return [ false, 'scriptpubkey' ] if !script.is_standard?

        if script.is_op_return?
          op_return_count += 1
        elsif txout_is_dust?(txout)
          return [ false, 'dust' ]
        end
      }

      # only one OP_RETURN output per tx allowed
      # no idea why bitcoind checks this outside of the loop above
      return [ false, 'multi-op-return' ] if op_return_count > 1

      # all good
      return [ true, nil ]
    end

    # Inspect pushes in the script
    def script_check_pushes(script, push_only=true, canonical_only=false)
      program = script.unpack("C*")
      until program.empty?
        opcode = program.shift
        if opcode > Bitcoin::Script::OP_16
          return false if push_only
          next
        end
        if opcode < Bitcoin::Script::OP_PUSHDATA1 && opcode > Bitcoin::Script::OP_0
          # Could have used an OP_n code, rather than a 1-byte push.
          return false if canonical_only && opcode == 1 && program[0] <= 16
          program.shift(opcode)
        end
        if opcode == Bitcoin::Script::OP_PUSHDATA1
          len = program.shift(1)[0]
          # Could have used a normal n-byte push, rather than OP_PUSHDATA1.
          return false if canonical_only && len < Bitcoin::Script::OP_PUSHDATA1
          program.shift(len)
        end
        if opcode == Bitcoin::Script::OP_PUSHDATA2
          len = program.shift(2).pack("C*").unpack("v")[0]
          # Could have used an OP_PUSHDATA1.
          return false if canonical_only && len <= 0xff
          program.shift(len)
        end
        if opcode == Bitcoin::Script::OP_PUSHDATA4
          len = program.shift(4).pack("C*").unpack("V")[0]
          # Could have used an OP_PUSHDATA2.
          return false if canonical_only && len <= 0xffff
          program.shift(len)
        end
      end
      true
    rescue => ex
      # catch parsing errors
      false
    end

    # Verify the script is only pushing data onto the stack
    def script_is_push_only?(script)
      script_check_pushes(script, push_only=true, canonical_only=false)
    end

    # Make sure opcodes used to push data match their intended length ranges
    def script_pushes_are_canonical?(script)
      script_check_pushes(script, push_only=false, canonical_only=true)
    end

    def txout_is_dust?(txout)
      size = 148 + txout.to_payload.bytesize
      return txout.value < 3*(Toshi::MIN_RELAY_TX_FEE * size / 1000)
    end

    # Check transaction inputs, and make sure any
    # pay-to-script-hash transactions are evaluating IsStandard scripts
    #
    # Why bother? To avoid denial-of-service attacks; an attacker
    # can submit a standard HASH... OP_EQUAL transaction,
    # which will get accepted into blocks. The redemption
    # script can be anything; an attacker could use a very
    # expensive-to-check-upon-redemption script like:
    #   DUP CHECKSIG DROP ... repeated 100 times... OP_1
    #
    # See AreInputsStandard in bitcoind.
    def are_inputs_standard?(tx, for_test=false)
      return true if tx.is_coinbase?

      tx.inputs.each do |txin|
        txout = @storage.output_for_outpoint(txin.prev_out, txin.prev_out_index, for_test)
        pk_script = Bitcoin::Script.new(txout.pk_script)
        # check that the script pubkey is standard
        return false if !pk_script.is_standard?
        num_args_expected = script_args_expected(pk_script)
        return false if num_args_expected < 0

        # parse the script sig
        script = Bitcoin::Script.new(txin.script)

        # check that serialized p2sh scripts are also standard
        if pk_script.is_p2sh?
          return false if script.chunks.length < 1
          serialized_script = script.chunks[-1]
          inner_script = Bitcoin::Script.new(serialized_script)
          return false if inner_script.is_p2sh? || !inner_script.is_standard?
          inner_num_args_expected = script_args_expected(inner_script)
          return false if inner_num_args_expected < 0
          num_args_expected += inner_num_args_expected
        end

        # we already know all of the script elements are pushes
        return false if num_args_expected != script.chunks.length
      end

      true
    end

    # Number of script args expected given a particular scriptPubKey format
    def script_args_expected(pk_script)
      return 1 if pk_script.is_pubkey?
      return 2 if pk_script.is_hash160?
      # +1 here for the extra OP_0 to account for bitcoind's OP_CHECKMULTISIG bug
      return pk_script.get_signatures_required+1 if pk_script.is_multisig?
      return 1 if pk_script.is_p2sh? # doesn't include args needed by the script
      -1
    end

    # Total number of satoshis in tx outputs.
    # Raises an exception if amount is out of valid range.
    # See CTransaction::GetValueOut() in bitcoind.
    def tx_value_out(tx)
      value = 0
      tx.outputs.each do |txout|
        value += txout.value
        if !valid_money_range(txout.value) || !valid_money_range(value)
          raise TxValidationError, "CTransaction::GetValueOut() : value out of range"
        end
      end
      value
    end

    # Total number of satoshis in tx inputs.
    # See CCoinsViewCache::GetValueIn() in bitcoind.
    def tx_value_in(tx)
      return 0 if tx.is_coinbase?
      value = 0
      tx.inputs.each do |txin|
        txout = @storage.output_for_outpoint(txin.prev_out, txin.prev_out_index)
        value += txout.value
      end
      return value
    end

    # See MoneyRange() in bitcoind.
    def valid_money_range(satoshis)
      return (satoshis >= 0 && satoshis <= Bitcoin.network[:max_money])
    end

    # Counts number of sigops inside a P2SH script.
    # See GetP2SHSigOpCount in bitcoind.
    def p2sh_sigops_count(tx)
      return 0 if tx.is_coinbase?

      sigops = 0
      tx.inputs.each do |txin|
        txout = @storage.output_for_outpoint(txin.prev_out, txin.prev_out_index)
        if txout.parsed_script.is_p2sh?
          sigops += ::Bitcoin::Script.new(txin.script_sig).sigops_count_for_p2sh
        end
      end

      return sigops
    end

    # Returns true if all of the inputs reference existing spendable outputs.
    # This is like view.HaveInputs() in bitcoind.
    def verify_inputs_are_available(tx, include_memory_pool=false)
      return true if tx.is_coinbase?
      outpoints = tx.inputs.map{|txin| [txin.prev_out, txin.prev_out_index] }
      mempool = include_memory_pool ? @mempool : nil
      return @storage.all_outpoints_are_available(tx.hash, outpoints, mempool)
    end

    # Scans up to <max> previous block headers starting with <block_header>
    # to find blocks with version >= <min_version>.
    # Returns true if found no less than <min> blocks.
    # E.g. verify_block_version_super_majority(2, block, 750, 1000) returns true if >= 750
    # blocks out of last 1000 are of version 2 or greater.
    def verify_block_version_super_majority(min_version, block_header, min_blocks, max_blocks)
      found = 0
      i = 0
      while i < max_blocks && found < min_blocks && block_header
        if block_header.ver >= min_version
          found += 1
        end
        block_header = @storage.previous_block_header_for_block_header(block_header)
        i += 1
      end
      return (found >= min_blocks)
    end

    # See GetTotalBlocksEstimate
    def max_checkpoint_height
      checkpoints = Bitcoin.network[:checkpoints] || {}
      checkpoints.keys.max || 0
    end

    # See Checkpoints::GetLastCheckpoint() in bitcoind.
    def latest_checkpoint_hash
      # Find the latest checkpoint that we have validated.
      checkpoints = Bitcoin.network[:checkpoints]
      # Start with the topmost checkpoint.
      checkpoints.keys.sort.reverse.each do |height|
        hash = checkpoints[height]
        # Only return validated checkpoints (not orphans)
        if @storage.is_block_valid?(hash)
          return hash
        end
      end
      return nil
    end

    def height_of_checkpoint(checkpoint_hash)
      checkpoints = Bitcoin.network[:checkpoints]
      checkpoints.each do |height, hash|
        if hash == checkpoint_hash
          return height
        end
      end
      return nil
    end

    def tx_is_final?(tx, block_height=0, block_time=0)
      if block_height == 0
        # TODO: shouldn't this just be height?
        block_height = Toshi::Models::Block.max_height
      end

      if block_time == 0
        block_time = NodeTime.adjusted_time
      end

      return tx.is_final?(block_height, block_time)
    end

    # https://github.com/bitcoin/bitcoin/blob/master/src/main.cpp around L762 GetNextWorkRequired
    # https://en.bitcoin.it/wiki/Protocol_rules#Difficulty_change
    def block_next_bits_required(block)
      # Maximum target is the minimum difficulty.
      max_target = Bitcoin.network[:proof_of_work_limit]

      # retarget interval in blocks (2016) - how often we change difficulty
      retarget_interval = Bitcoin.network[:retarget_interval]

      # target interval for 2016 blocks in seconds (1209600) - what is the ideal interval between the blocks
      retarget_time = Bitcoin.network[:retarget_time]

      # target interval between blocks (10 minutes)
      target_spacing = Bitcoin.network[:target_spacing]

      if block.hash == Bitcoin.network[:genesis_hash]
        return max_target
      end

      prev_block_header = @storage.block_header_for_hash(block.prev_block_hex)
      prev_height       = @storage.height_for_block_header(prev_block_header)
      prev_time         = prev_block_header.time

      # If this is not 2016th block, find the previous block and use its difficulty.
      # Rules are more complex for testnet.
      if ((prev_height + 1) % retarget_interval) != 0
        if is_testnet?
          # Special difficulty rule for testnet:
          # If the new block's timestamp is more than 2*10 minutes
          # then allow mining of a min-difficulty block.
          if block.time > (prev_time + (target_spacing*2))
            return max_target
          else
            # Return the last non-special-min-difficulty-rules-block
            prev = prev_block_header
            while (prev && (@storage.height_for_block_header(prev) % retarget_interval) != 0 && prev.bits == max_target)
              prev = @storage.previous_block_header_for_block_header(prev)
            end
            return prev.bits
          end
        end
        # Mainnet: simply use previous block difficulty.
        return prev_block_header.bits
      end # not 2016th block

      # We are on 2016th block, need to find the previous 2016th block and calculate how much to change the difficulty.
      # Go back by what we want to be 14 days worth of blocks within the correct chain.
      # We should not assume anything regarding main/side chain.
      first = prev_block_header
      i = 0
      while first && i < (retarget_interval - 1)
        first = @storage.previous_block_header_for_block_header(first)
        i += 1
      end

      # Sanity check: block should always be there
      if !first
        raise RuntimeError, "should always be able to find previous retarget block (at very least, a genesis one)"
      end

      # actual timespan is 2 weeks (retarget_time)
      actual_timespan = prev_block_header.time - first.time

      min = retarget_time / 4
      max = retarget_time * 4

      actual_timespan = min if actual_timespan < min
      actual_timespan = max if actual_timespan > max

      # It could be a bit confusing: we are adjusting difficulty of the previous block, while logically
      # we should use difficulty of the previous 2016th block ("first")

      prev_target = Bitcoin.decode_compact_bits(prev_block_header.bits).to_i(16)

      new_target = prev_target * actual_timespan / retarget_time

      # if new target is above the max target, use the
      if new_target > Bitcoin.decode_compact_bits(max_target).to_i(16)
        trace_step { "block_next_bits_required: new_target > max_target; returning max_target" }
        max_target
      else
        trace_step { "block_next_bits_required: returning new_target." }
        Bitcoin.encode_compact_bits(new_target.to_s(16))
      end
    end

    # Finds at most 11 blocks starting with this one and returns a median timestamp.
    # Used to prevent accepting blocks with too early timestamps.
    # See GetMedianTimePast() in bitcoind.
    def block_median_timestamp_for_block_header(block_header)
      median_timespan = 11
      timestamps = []
      i = 0
      prev = block_header
      while i < median_timespan && prev
        timestamps << prev.time
        prev = @storage.previous_block_header_for_block_header(prev)
        i += 1
      end

      # Return a median timestamp
      timestamps.sort[timestamps.size / 2].to_i
    end

    # Verifies that block hash matches the declared target ("bits")
    # See CheckProofOfWork() in bitcoind.
    def check_proof_of_work(block)
      if Bitcoin.network_name == :litecoin
        actual = block.recalc_block_scrypt_hash.to_i(16)
      else
        actual = block.hash.to_i(16)
      end

      expected_target = Bitcoin.decode_compact_bits(block.bits).to_i(16)
      max_target = Bitcoin.decode_compact_bits(Bitcoin.network[:proof_of_work_limit]).to_i(16)

      # Check the range.
      if expected_target <= 0 || (max_target > 0 && expected_target > max_target)
        return false
      end

      # Check the POW.
      return (actual <= expected_target)
    end

    # Minimum amount of work that could possibly be required <time> after minimum work required was <base_work>
    # See ComputeMinWork() in bitcoind, but this one takes and returns bignum instead of compact int.
    def compute_min_work(base_work, time)
      max_target = Bitcoin.decode_compact_bits(Bitcoin.network[:proof_of_work_limit]).to_i(16)

      # Testnet has min-difficulty blocks after nTargetSpacing*2 time between blocks:
      target_spacing = (Bitcoin.network[:retarget_time] / Bitcoin.network[:retarget_interval])
      if is_testnet? && time > target_spacing*2
        return max_target
      end

      result = base_work
      while time > 0 && result < max_target
        # Maximum 400% adjustment...
        result *= 4
        # ... in best-case exactly 4-times-normal target time
        time -= Bitcoin.network[:retarget_time]*4
      end
      if result > max_target
        result = max_target
      end
      return result
    end

    def is_testnet?
      [:testnet, :testnet3].include?(Bitcoin.network_name)
    end

    def require_standard?
      Bitcoin.network_name == :bitcoin && !@allow_nonstandard_tx_on_mainnet
    end

    # Mark inputs as spent and add new outputs as unspent.
    # See UpdateCoins in bitcoind.
    def update_unspent_outputs(tx)
      if !tx.is_coinbase?
        tx.inputs.each do |txin|
          @storage.mark_output_as_spent(txin.prev_out, txin.prev_out_index)
        end
      end

      # Add unspent output
      tx.outputs.each_with_index do |txout, i|
        @storage.mark_output_as_unspent(tx.binary_hash, i)
      end
    end

    # Persistence helpers

    # Saves the block as a part of the main chain.
    def persist_block_on_main_branch(block, height, prev_work=0)
      start_time = Time.now
      #puts "Saving block on main chain: #{height}:#{block.hash} previous work: #{prev_work}"
      result = @storage.save_block_on_main_branch(block, height, prev_work)
      measure_method(:persist_block_on_main_chain, start_time)
      msg = "persist_block processing time: #{(Time.now - start_time).to_f}"
      log_raw_block_events(block.hash, msg)
      msg = "process_block total time: #{(Time.now - @processing_start_time).to_f}"
      log_raw_block_events(block.hash, msg)

      result
    end

    # Saves the block as a part of some side chain.
    def persist_block_on_side_branch(block, height, prev_work=0)
      start_time = Time.now
      result = @storage.save_block_on_side_branch(block, height, prev_work)
      msg = "persist_block processing time: #{(Time.now - start_time).to_f}"
      log_raw_block_events(block.hash, msg)
      msg = "process_block total time: #{(Time.now - @processing_start_time).to_f}"
      log_raw_block_events(block.hash, msg)

      result
    end

    def persist_orphan_block(block, height)
      start_time = Time.now
      result = @storage.save_orphan_block(block, height)

      msg = "persist_block processing time: #{(Time.now - start_time).to_f}"
      log_raw_block_events(block.hash, msg)
      msg = "process_block total time: #{(Time.now - @processing_start_time).to_f}"
      log_raw_block_events(block.hash, msg)

      result
    end

    # Utilities

    def log_raw_block_events(block_hash, msg)
      logger.debug{ "%s %s" % [block_hash, msg] }
    end

    def log_raw_tx_events(tx_hash, msg)
      logger.debug{ "%s %s" % [tx_hash, msg] }
    end

    def log
      @logger
    end

    # Extra step-by-step logging

    # Enables tracing within the block
    def trace_execution_steps(&block)
      begin
        @trace_execution_steps_counter += 1
        yield
      ensure
        @trace_execution_steps_counter -= 1
      end
    end

    # Traces a single step.
    def trace_step(&block)
      if @trace_execution_steps_counter > 0
        puts "Trace: " + yield.to_s
      end
    end
  end
end
