require "sidekiq"

module Toshi
  module Workers
    class BlockWorker
      include Sidekiq::Worker

      sidekiq_options queue: :blocks, :retry => true

      def perform(block_hash, _sender)
        if Toshi::Models::Block.main_branch.where(hsh: block_hash).empty? &&
          raw_block = Toshi::Models::RawBlock.where(hsh: block_hash).first

          begin
            result = processor.process_block(raw_block.bitcoin_block, raise_error=true)
          rescue Toshi::Processor::ValidationError => ex
            # we want anything else to blow up
            logger.warn{ ex.message }
          end

          if result
            block = Toshi::Models::Block.where(hsh: block_hash).first
            if block.previous.nil? || block.previous.is_orphan_chain?
              # if we just persisted this block as an orphan we should send another
              # 'getblocks' back to the peer who sent us this block.
              RedisMQ::Channel.reply_to_peer(_sender, 'msg' => 'get_blocks')
            end
          else
            # don't save rejected blocks
            raw_block.delete
          end

          logger.info{ result }
        end

        # let the connection know we've processed this block so it can potentially send us more.
        RedisMQ::Channel.reply_to_peer(_sender, { 'msg' => 'block_processed', 'block_hash' => block_hash })
      end

      def processor
        # this way we can make effective use of the block header cache/index
        # it's safe because the block processor only has a single thread
        @@processor ||= Toshi::Processor.new
      end
    end
  end
end
