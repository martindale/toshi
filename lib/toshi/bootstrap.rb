module Toshi
  class Bootstrap
    # Set to true when processing should finish safely.
    attr_accessor :should_exit

    # Set to true to wipe out all records and start from genesis block.
    attr_accessor :start_from_scratch

    # False by default.
    attr_accessor :checkpoints_enabled

    # Path to a file from where to read all the blocks to be processed.
    attr_accessor :bootstrap_file

    # Import up to this number of blocks. Default is 2**32.
    attr_accessor :max_blocks

    def initialize(bootstrap_file)
      @bootstrap_file = bootstrap_file
      @max_blocks = 2**32
    end

    def run
      #Bitcoin.network = :testnet3

      processor = Toshi::Processor.new
      processor.verbose_logging = true

      #processor.debug_skip_proof_of_work_check  = true

      # Disable checkpoints to force all scripts to be executed.
      processor.checkpoints_disabled = !@checkpoints_enabled
      if processor.checkpoints_disabled
        puts "Checkpoints disabled."
      else
        puts "Checkpoints enabled."
      end

      if @start_from_scratch
        system "rake db:migrate"
      end

      unless Toshi::Models::Block.head
        start_height = 0
      else
        start_height = @start_from_scratch ? 0 : (Toshi::Models::Block.head.height + 1)
      end
      start_offset = 0; #@start_from_scratch ? 0 : File.read("#{Toshi.root}/bootstrap_last_offset.txt").to_s.to_i rescue 0

      if @start_from_scratch
        puts "Starting from scratch."
      else
        puts "Starting from block #{start_height}."
      end

      previous_trap = trap("SIGINT") do
        @should_exit = true
      end

      blocks_counter = @max_blocks || 2**32

      avg_tx_count = 1.0
      avg_time_per_block = 0.3

      Toshi::Utils.read_bootstrap_file(@bootstrap_file, 0, -1, start_height) do |block,height,offset|
        if blocks_counter > 0

          blocks_counter -= 1

          t = Time.now.to_f
          result = processor.process_block(block, raise_errors=true)
          b = Toshi::Models::Block.where(hsh: block.hash).first

          delta = (Time.now.to_f - t)

          avg_tx_count = 0.99*avg_tx_count + 0.01*block.tx.size
          avg_time_per_block = 0.99*avg_time_per_block + 0.01*delta

          blocks_in_hour = 3600.0 / avg_time_per_block

          puts "%d (%d) %s %3d tx (%0.1f avg) %0.4f sec %0.0f blocks/hour" % [b.height, b.branch, b.hsh, block.tx.size, avg_tx_count, delta, blocks_in_hour]
          if !result
            puts "Can't process the block #{height}:#{b.hsh}"
            @should_exit = true
          end

          if @should_exit
            File.open("#{Toshi.root}/bootstrap_last_offset.txt", "w"){|f| f.write(offset.to_s) }
            puts "Stopping after processing block #{b.height}:#{b.hsh}."
            # Restore previous trap.
            trap("SIGINT", previous_trap)
            false
          else
            true
          end
        else
          false
        end
      end

      self
    end
  end
end
