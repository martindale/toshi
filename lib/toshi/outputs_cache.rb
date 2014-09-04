module Toshi

  # Implements a structure similar to bitcoind's CCoinsViewCache.
  # Valid unspent outputs are stored in the cache and available instantly.
  class OutputsCache

    # Reference to BlockchainStorage instance so we can retrieve outpoints automatically.
    # Can be nil, in which case outpoints are not loaded/inserted automatically.
    attr_accessor :storage

    def initialize
      @storage = nil

      # Array contains pair of TxOut instance and spent flag: nil, true or false.
      # nil   - unknown status
      # false - not spent
      # true  - spent
      # txhash => [ [TxOut, spent_flag], ...  ]
      @spent_outpoints = {}

      # txhash => true/false
      @is_coinbase = {}
    end

    def flush
      @spent_outpoints = {}
      @is_coinbase = {}
    end

    # return a cached copy of the output model
    def output_from_model_cache(binary_tx_hash, index)
      txout = self.output_for_outpoint(binary_tx_hash, index)
      txout.instance_variable_get(:@cached_model) rescue nil
    end

    def mark_output_as_spent(binary_tx_hash, output_index, spent, if_exists = false)
      if !if_exists || @spent_outpoints[binary_tx_hash]
        ((@spent_outpoints[binary_tx_hash] ||= [])[output_index] ||= [])[1] = spent
        #puts "SET Spent for #{binary_tx_hash.unpack('H*').first} - #{output_index} = #{spent.inspect} [cache: #{@spent_outpoints.size}]"
      end
      self
    end

    def mark_output_as_not_available(binary_tx_hash, output_index, if_exists = false)
      if !if_exists || @spent_outpoints[binary_tx_hash]
        ((@spent_outpoints[binary_tx_hash] ||= [])[output_index] ||= [])[1] = nil
      end
      self
    end

    # To implement BIP30, must be equivalent to (view.HaveCoins(hash) && !view.GetCoins(hash).IsPruned())
    # Return true if there is one unspent output for any of the transactions. This will fail BIP30 right away.
    # Returns false also when there's not enough data.
    def has_previously_unspent_outputs_for_any_tx_hash(bin_tx_hashes)
      # TODO: implement this, but this won't improve performance a lot.
      return false
    end

    # Returns true if there are some outputs available for all of the binary hashes given
    # Returns false when there's not enough data.
    def has_outputs_for_all_tx_hashes(binary_tx_hashes)
      # TODO: implement this, but this is not used now.
      return false
    end

    # Returns true, false or nil if data is missing.
    def outpoint_is_spent(txhash,i)
      ((@spent_outpoints[txhash] || [])[i] || [])[1]
    end

    # Returns true if every outpoint is not spent yet.
    # Each outpoint is [binary_tx_hash, out_index]
    def all_outpoints_are_unspent(outpoints)
      outpoints.each do |txhash, i|
        spent = ((@spent_outpoints[txhash] || [])[i] || [])[1]
        #puts "Spent for #{txhash.unpack('H*').first} - #{i} = #{spent.inspect} [cache: #{@spent_outpoints.size}]"
        if spent == nil || spent == true
          return false
        end
      end
      return true
    end

    # Returns TxOut object for the given outpoint.
    def output_for_outpoint(binary_tx_hash, out_index)
      ((@spent_outpoints[binary_tx_hash] || [])[out_index] || [])[0]
    end

    def set_output_for_outpoint(binary_tx_hash, out_index, txout)
      ((@spent_outpoints[binary_tx_hash] ||= [])[out_index] ||= [])[0] = txout
    end

    # Returns true if the transaction is a coinbase, false otherwise.
    # Returns nil if the data is missing.
    def is_tx_coinbase(binary_tx_hash)
      @is_coinbase[binary_tx_hash]
    end

    def set_tx_coinbase(binary_tx_hash, is_coinbase)
      @is_coinbase[binary_tx_hash] = is_coinbase
    end

  end
end
