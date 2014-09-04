require 'spec_helper'

describe Toshi::Processor, :performance do
  describe '#process_block_peformance' do

    it 'processes a block with many inputs and many outputs' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("many_inputs_many_outputs_chain.json")
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
      }
    end
  end
end
