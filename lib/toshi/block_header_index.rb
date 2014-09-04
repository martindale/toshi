module Toshi

  # Implements a structure similar to bitcoind's mapBlockIndex
  # Valid block headers are stored in memory (main/side chain) and
  # allow to efficiently navigate back in the chain.
  # Index provides lazy fill (so we don't need to read the whole DB on startup).
  # It finds block headers in the storage if they are missing and adds them automatically.
  # Has optional limit to keep at most N blocks in memory.

  class BlockHeaderIndex

    # Reference to BlockchainStorage instance so we can retrieve block headers automatically.
    # Can be nil, in which case blocks are not loaded/inserted automatically.
    attr_accessor :storage

    # Maximum number of blocks to be kept in memory.
    # When another block is inserted, some random block is pruned.
    # If 0, blocks are never pruned.
    # Default is 0, all block headers are kept in memory.
    attr_accessor :item_limit

    def initialize
      @storage = nil
      @item_limit = 0
      @headers_by_hash = {}
      @headers_count = 0

      # FIXME: will we ever really need it?
      @tips_hashes = [] # array of chain "tips" - one of the hashes is a tip of the main chain.
    end

    # returns a block header for hash or nil if it's not found.
    # attempts to load a block from storage if it exists
    def block_header_for_hash(hash)
      # return existing header or try to load one from storage if we have one.
      @headers_by_hash[hash] ||= begin
        if @storage
          block = @storage.valid_block_for_hash(hash)
          if block

            block_header = block_header_from_block(block)

            # If we have a previous block, use its height and total_work.
            # Otherwise, load them from the DB.

            if prev_block_header = @headers_by_hash[block_header.hash]
              block_header.height = (prev_block_header.height + 1) if prev_block_header.height
              block_header.total_work = prev_block_header.total_work + block.block_work
            else
              block_header.height = @storage.height_for_block(block.hash)
              block_header.total_work = @storage.total_work_up_to_block_hash(block.hash)
            end
            @headers_count += 1
            prune_blocks(block_header.hash)
            block_header
          else
            nil
          end
        end
      end
    end

    # Quick check if the block header is in index
    def block_header_in_index?(hash)
      !!@headers_by_hash[hash]
    end

    # Inserts a block header based on block (if it's not there yet).
    # If previous block is not included in index, raises an exception.
    # Argument is an instance of Bitcoin::Protocol::Block
    def insert_block(block, height = nil, prev_work = 0)
      if @headers_by_hash[block.hash]
        return
      end
      block_header = block_header_from_block(block)
      block_header.height = height if height
      block_header.total_work = prev_work + block.block_work
      @headers_by_hash[block.hash] = block_header
      @headers_count += 1
      prune_blocks(block_header.hash)
    end

    def remove_block(block)
      @headers_count -= 1 if @headers_by_hash.delete(block.hash)
    end

    # Removes excessive blocks according to @item_limit
    def prune_blocks(seed_hash = nil)

      # Do nothing if limit is not set.
      return if (@item_limit || 0) < 1

      while @headers_count > @item_limit
        # Remove some random block and make sure to break references to it from all of its children.
        # Do not use rand(), but use block hashes to determine an index to remove.
        # This will greatly help with debugging.

        # Since Ruby 1.9 has keys sorted by order of use, we will remove the oldest key first.
        random_index = 0 # if seed_hash
        #           # reverse hash (because its beginning in hex form is all-zero)
        #           [seed_hash].pack("H*").reverse.unpack("V").first % @headers_count
        #         else
        #           # no seed hash - use shitty random number generator
        #           rand(@headers_count)
        #         end

        # Find random object
        if obj_hash = @headers_by_hash.keys[random_index]
          obj = @headers_by_hash[obj_hash]

          if obj
            # Break references from its children:
            (obj.next_block_headers || []).each do |child|
              child.previous_block_header = nil
            end

            # Cleanup
            obj.next_block_headers = nil

            # Update counter
            @headers_count -= 1
          end

          # Remove item from the index
          @headers_by_hash.delete(obj_hash)
        end

      end
    end

    private

    def block_header_from_block(block)
      block_header = BlockHeader.new
      block_header.block_header_index = self # reference to its parent
      block_header.hash            = block.hash
      block_header.ver             = block.ver
      block_header.prev_block      = block.prev_block
      block_header.prev_block_hex  = block.prev_block_hex
      block_header.mrkl_root       = block.mrkl_root
      block_header.time            = block.time
      block_header.bits            = block.bits
      block_header.nonce           = block.nonce
      block_header
    end

    # Concrete item for the index.
    class BlockHeader
      # Reference to an index that owns this block_header
      attr_accessor :block_header_index

      # Hash of this block
      attr_accessor :hash

      # Reference to the previous block header
      attr_accessor :previous_block_header

      # List of next block headers (private ivar, it is updated only when the child links to this block)
      attr_accessor :next_block_headers

      # block version
      attr_accessor :ver

      # previous block hash (binary)
      attr_accessor :prev_block

      # previous block hash (lowercase hex string)
      attr_accessor :prev_block_hex

      # merkle root of transactions (binary)
      attr_accessor :mrkl_root

      # block generation time - 32-bit unix timestamp
      attr_accessor :time

      # difficulty in "compact" integer encoding
      attr_accessor :bits

      # nonce (number counted when searching for block hash matching target)
      attr_accessor :nonce

      # Extensions:
      attr_accessor :height
      attr_accessor :total_work # cumulative work

      # compare headers by hash
      def ==(other)
        self.hash == other.hash
      end

      def previous_block_header
        # Return linked block header or try to load it dynamically from the index.
        @previous_block_header ||= begin
          if self.prev_block # skip genesis block
            prev = @block_header_index.block_header_for_hash(self.prev_block_hex)

            # Should let ancestor know about the child block that references it, so
            # ancestor can break this reference when being pruned from the index.
            if prev
              prev.next_block_headers ||= []
              if !prev.next_block_headers.include?(self)
                prev.next_block_headers << self
              end
            end
            prev
          end
        end
      end

    end
  end
end
