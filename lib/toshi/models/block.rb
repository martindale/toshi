module Toshi
  module Models
    class Block < Sequel::Model

      MAIN_BRANCH   = 0 # current longest branch
      SIDE_BRANCH   = 1 # not in the current longest branch but shares a root with the main branch
      ORPHAN_BRANCH = 2 # in a branch with no shared root with the main branch

      BRANCH_TABLE = {
        MAIN_BRANCH   => 'main',
        SIDE_BRANCH   => 'side',
        ORPHAN_BRANCH => 'orphan'
      }

      many_to_many :transactions, :order => :position

      def self.main_branch
        filter(branch: MAIN_BRANCH)
      end

      def self.side_branch
        filter(branch: SIDE_BRANCH)
      end

      def self.main_or_side_branch
        filter(branch: [MAIN_BRANCH, SIDE_BRANCH])
      end

      def self.orphan_branch
        filter(branch: ORPHAN_BRANCH)
      end

      # compute blockchain locator
      def self.getblocks_locator(pointer=Block.head)
        orig_pointer = pointer
        if @locator
          locator, head = @locator
          return locator if head == pointer
        end

        locator, step = [], 1
        while pointer && pointer.hsh != Bitcoin::network[:genesis_hash]
          locator << pointer.hsh
          depth = pointer.height - step
          break unless depth > 0
          prev_block = Block.main_branch.where(height: depth).first
          break unless prev_block
          pointer = prev_block
          step *= 2  if locator.size > 10
        end
        locator << Bitcoin::network[:genesis_hash]
        @locator = [locator, orig_pointer]
        locator
      end

      def bitcoin_block
        Bitcoin::P::Block.new(RawBlock.where(hsh: hsh).first.payload)
      end

      def branch_name
        BRANCH_TABLE[branch] || "unkown"
      end

      def is_main_chain?
        return branch == MAIN_BRANCH
      end

      def is_side_chain?
        return branch == SIDE_BRANCH
      end

      def is_orphan_chain?
        return branch == ORPHAN_BRANCH
      end

      def previous
        @previous_block ||= Block.where(hsh: prev_block).first
      end

      def previous_blocks
        @previous_blocks ||= Block.where(hsh: prev_block)
      end

      def next
        @next_block ||= Block.where(prev_block: hsh).first
      end

      def next_blocks
        @next_blocks ||= Block.where(prev_block: hsh)
      end

      def confirmations(max_height=nil)
        max_height = Block.max_height if !max_height
        branch == MAIN_BRANCH ? (max_height - height) : 0
      end

      # The latest block on the main branch, aka "chainActive.Tip()" in bitcoind.
      def self.head
        main_branch.order(:height).last
      end

      def self.max_height
        head.height rescue 0
      end

      # Total work from genesis block to this one (aka nChainWork in bitcoind)
      # Not to be confused with Bitcoin::Protocol::Block#block_work which is per-block work
      def block_work
        self.work.unpack("H*")[0].to_i(16)
      end

      def raw
        Toshi::Models::RawBlock.where(hsh: hsh).first
      end

      # calculate additional fields not part of the protocol
      def self.calculate_additional_fields(block, branch)
        fields = { total_in_value: 0, total_out_value: 0, fees: 0 }
        return fields if branch != Block::MAIN_BRANCH

        block.tx.each do |tx|
          if tx.is_coinbase?
            value_out = tx.outputs.inject(0){|acc,output| acc + output.value }
            tx.additional_fields = { total_in_value: 0, total_out_value: value_out, fee: 0 }
            fields[:total_out_value] += value_out
            next
          end

          fields[:total_in_value]  += tx.additional_fields[:total_in_value]
          fields[:total_out_value] += tx.additional_fields[:total_out_value]
          fields[:fees]            += tx.additional_fields[:fee]
        end

        fields
      end

      # <block> is an instance of Bitcoin::Protocol::Block
      # <height> is this block's height. If nil, will be loaded automatically from the previous block and incremented.
      def self.create_from_block(block, height=nil, branch=Block::MAIN_BRANCH, output_cache=nil, prev_work=0)
        payload = block.payload || block.to_payload
        RawBlock.new(hsh: block.hash, payload: Sequel.blob(payload)).save unless !RawBlock.where(hsh: block.hash).empty?

        height = height || ((Block.where(hsh: block.prev_block_hex).first.height rescue 0) + 1)

        # calculate additional fields
        fields = calculate_additional_fields(block, branch)

        b = Block.where(hsh: block.hash).first || b = Block.new({
          hsh:                block.hash,
          prev_block:         block.prev_block_hex,
          mrkl_root:          block.mrkl_root.reverse_hth,
          time:               block.time,
          bits:               block.bits,
          nonce:              block.nonce,
          ver:                block.ver,
          branch:             branch,
          height:             height,
          size:               payload.bytesize,
          work:               Sequel.blob(OpenSSL::BN.new((prev_work + block.block_work).to_s).to_s(0)[4..-1]),
          transactions_count: block.tx.size,
          total_in_value:     fields[:total_in_value],
          total_out_value:    fields[:total_out_value],
          fees:               fields[:fees]
        })

        if b.branch != branch
          b.work            = Sequel.blob(OpenSSL::BN.new((prev_work + block.block_work).to_s).to_s(0)[4..-1])
          b.branch          = branch
          b.height          = height
          b.total_in_value  = fields[:total_in_value]
          b.total_out_value = fields[:total_out_value]
          b.fees            = fields[:fees]
        end

        b.save

        tx_index_hash = {}
        all_tx_hashes = []

        block.tx.each_with_index do |tx,tx_index|
          tx_index_hash[tx.hash] = tx_index
          all_tx_hashes << tx.hash
        end

        tx_associations = []
        tx_hsh_to_id = {}

        pool = branch == MAIN_BRANCH ? Transaction::TIP_POOL : Transaction::BLOCK_POOL

        # find existing txs and associate them with the block
        # and update their display fields as well.
        Transaction.where(hsh: all_tx_hashes).each do |t|
          tx_index = tx_index_hash[t.hsh]
          tx_associations << { transaction_id: t.id, block_id: b.id, position: tx_index }
          tx_index_hash.delete(t.hsh)
          tx_hsh_to_id[t.hsh] = t.id
          t.remove_block(b) # there's probably a more graceful way to avoid dups
          t.height = b.height if b.is_main_chain?
          fields = block.tx[tx_index].additional_fields || {}
          # update additional fields
          t.total_in_value  = fields[:total_in_value] || 0
          t.total_out_value = fields[:total_out_value] || 0
          t.fee             = fields[:fee] || 0
          t.save
        end

        # create any txs that didn't already exist in the db
        if tx_index_hash.any?
          # containers for hashes we plan on bulk importing at once
          transactions, block_inputs, block_outputs = [], [], []
          block_input_addresses, block_output_addresses = [], []

          tx_index_hash.each do |tx_hash, tx_index|
            t, inputs, input_addresses, outputs, output_addresses =
              Transaction.create_from_tx(block.tx[tx_index], pool, branch, output_cache, b, tx_index)
            transactions << t
            block_inputs += inputs
            block_input_addresses += input_addresses
            block_outputs += outputs
            block_output_addresses += output_addresses
          end

          # batch import the txs
          tx_ids = Transaction.multi_insert(transactions, {:return => :primary_key})
          tx_ids.each_with_index do |tx_id, i|
            tx_hash = transactions[i][:hsh]
            tx_associations << { transaction_id: tx_id, block_id: b.id, position: tx_index_hash[tx_hash] }
            tx_hsh_to_id[tx_hash] = tx_id
          end

          # batch import the outputs, inputs, and upsert addresses
          Transaction.multi_insert_outputs(tx_hsh_to_id, block_outputs, block_output_addresses, branch)
          Transaction.multi_insert_inputs(tx_hsh_to_id, block_inputs, block_input_addresses, output_cache, branch, b.fees)
        end

        # batch import associations
        Toshi.db[:blocks_transactions].multi_insert(tx_associations)

        [b, "Created block #{b.hsh} with height #{b.height} on branch #{b.branch} with #{b.transactions.count} transactions"]
      end

      def to_hash(show_txs=false, offset=0, limit=100)
        offset = 0 if !offset
        limit = 100 if !limit
        self.class.to_hash_collection([self], show_txs, offset, limit).first
      end

      def self.to_hash_collection(blocks, show_txs=false, offset=0, limit=100)
        offset = 0 if !offset
        limit = 100 if !limit
        collection = []

        blocks.each{|block|
          hash = {}

          # needed for serialization roundtrips: hash, previous_block_hash, merkle_root (for sanity check), time, nonce, bits, version
          hash[:hash] = block.hsh
          hash[:branch] = block.branch_name
          hash[:previous_block_hash] = block.prev_block
          hash[:next_blocks] = block.next_blocks.map{|b| { hash: b.hsh, branch: b.branch_name, height: b.height } }
          hash[:height] = block.height
          hash[:confirmations] = block.confirmations
          hash[:merkle_root] = block.mrkl_root
          hash[:time] = Time.at(block.time).utc.iso8601
          hash[:created_at] = Time.at(block.created_at).utc.iso8601
          hash[:nonce] = block.nonce
          hash[:bits] = block.bits
          hash[:difficulty] = Bitcoin.block_difficulty(block.bits).to_f
          hash[:reward] = Bitcoin.block_creation_reward(block.height)
          hash[:fees] = block.fees
          #hash[:total_in] = block.total_in_value
          hash[:total_out] = block.total_out_value
          hash[:size] = block.size
          hash[:transactions_count] = block.transactions_count
          hash[:version] = block.ver

          if show_txs
            hash[:transactions] = Transaction.to_hash_collection(block.transactions)
          else
            hash[:transaction_hashes] = block.transactions.map {|tx| tx.hsh }
          end

          collection << hash
        }

        return collection
      end

      def to_json(show_txs=false, offset=0, limit=100)
        offset = 0 if !offset
        limit = 100 if !limit
        to_hash(show_txs, offset, limit).to_json
      end
    end
  end
end
