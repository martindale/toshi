require 'spec_helper'

describe Toshi::Processor do
  describe '#process_block' do
    COINBASE_REWARD = 5000000000 # units = satoshis

    it 'processes simple chain 1' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      # make sure processing blocks is idempotent
      2.times {
        blockchain.load_from_json("simple_chain_1.json")
        last_height = 0
        blockchain.chain['main'].each{|height, block|
          processor.process_block(block, raise_errors=true)
          last_height = height.to_i
        }

        expect(Toshi::Models::Block.count).to eq(8)
        expect(Toshi::Models::Block.max_height).to eq(7)
        expect(Toshi::Models::Transaction.count).to eq(9)
        expect(Toshi::Models::Address.count).to eq(10)

        # look for the tx to 2 unique addresses in block 7
        tx_hash = blockchain.chain['main']['7'].tx[1].hash

        address = blockchain.address_from_label('first recipient')
        expect(Toshi::Models::Address.where(address: address).first.balance).to eq(2500000000)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
        expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.position).to eq(0)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.hsh).to eq(tx_hash)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.transaction.hsh).to eq(tx_hash)

        address = blockchain.address_from_label('second recipient')
        expect(Toshi::Models::Address.where(address: address).first.balance).to eq(2500000000)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
        expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.position).to eq(1)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.hsh).to eq(tx_hash)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.transaction.hsh).to eq(tx_hash)

        # look for the deduction from the coinbase output in block 1
        tx = blockchain.chain['main']['1'].tx[0]
        tx_hash = tx.hash
        address = Bitcoin::Script.new(tx.outputs[0].script).get_address
        expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
        expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
        expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
        expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.hsh).to eq(tx_hash)
        expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.transaction.hsh).to eq(tx_hash)

        # look at additional fields
        i = 0
        while i < last_height do
          bitcoin_block = blockchain.chain['main'][i.to_s]
          block = Toshi::Models::Block.where(hsh: bitcoin_block.hash).first
          expect(block.transactions_count).to eq(bitcoin_block.tx.size)
          expect(block.total_in_value).to eq(0)
          if i < 7
            expect(block.total_out_value).to eq(COINBASE_REWARD)
          else
            # last block sends the reward from block 1 to 2 outputs
            expect(block.total_out_value).to eq(COINBASE_REWARD*2)
          end
          i += 1
        end
      }
    end

    it 'processes simple chain 2 fees' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("simple_chain_2.json")
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
      }

      expect(Toshi::Models::Block.count).to eq(10)
      expect(Toshi::Models::Block.max_height).to eq(9)
      expect(Toshi::Models::Transaction.count).to eq(12)
      expect(Toshi::Models::Address.count).to eq(12)

      block_hash = blockchain.chain['main']['0'].hash
      expect(Toshi::Models::Block.where(hsh: block_hash).first.fees).to eq(0)

      # block height 7
      block_hash = blockchain.chain['main']['7'].hash
      tx_hash = blockchain.chain['main']['7'].tx[0].hash

      expect(Toshi::Models::Block.where(hsh: block_hash).first.height).to eq(7)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.fee).to eq(0)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.block.hsh).to eq(block_hash)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.total_out_value).to eq(5000100000)

      tx_hash = blockchain.chain['main']['7'].tx[1].hash
      expect(Toshi::Models::Block.where(hsh: block_hash).first.fees).to eq(100000)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.fee).to eq(100000)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.block.hsh).to eq(block_hash)

      # block height 8
      block_hash = blockchain.chain['main']['8'].hash
      tx_hash = blockchain.chain['main']['8'].tx[0].hash

      expect(Toshi::Models::Block.where(hsh: block_hash).first.height).to eq(8)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.fee).to eq(0)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.block.hsh).to eq(block_hash)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.total_out_value).to eq(5000050000)

      tx_hash = blockchain.chain['main']['8'].tx[1].hash
      expect(Toshi::Models::Block.where(hsh: block_hash).first.fees).to eq(50000)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.fee).to eq(50000)
      expect(Toshi::Models::Transaction.where(hsh: tx_hash).first.block.hsh).to eq(block_hash)

      tx_hash = blockchain.chain['main']['7'].tx[1].hash
      address = blockchain.address_from_label('first recipient')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.position).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.transaction.hsh).to eq(tx_hash)

      address = blockchain.address_from_label('second recipient')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(4999850000)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(2)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)

      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.where(hsh: tx_hash).first
      expect(output.position).to eq(1)
      expect(output.amount).to eq(2499950000)
      expect(output.transaction.hsh).to eq(output.hsh)

      tx_hash = blockchain.chain['main']['8'].tx[1].hash
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.where(hsh: tx_hash).first
      expect(output.position).to eq(0)
      expect(output.amount).to eq(2499900000)
      expect(output.transaction.hsh).to eq(output.hsh)
    end

    it 'processes block validation rules syntax' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("block_validation_rules.json")
      blockchain.chain['main'].each{|height, block|
        break if block.is_a?(Array)
        processor.process_block(block, raise_errors=true)
      }

      expect(Toshi::Models::Block.count).to eq(8)

      expect {
        processor.process_block(blockchain.chain['main']['8'][0], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : size limits failed')
      expect {
        processor.process_block(blockchain.chain['main']['8'][1], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : proof of work failed')
      expect {
        processor.process_block(blockchain.chain['main']['8'][2], raise_errors=true, blockchain.chain['main']['8'][2].time-7300)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : block timestamp too far in the future')
      expect {
        processor.process_block(blockchain.chain['main']['8'][2], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : more than one coinbase')

      b = blockchain.chain['main']['8'][3]
      old_script = b.tx.first.inputs.first.script
      b.tx.first.inputs.first.script = old_script + ('A'*100)
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : coinbase script size')
      b.tx.first.inputs.first.script = old_script

      b = blockchain.chain['main']['8'][3]
      old_script = b.tx.first.inputs.first.script
      b.tx.first.inputs.first.script = "A"
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : coinbase script size')
      b.tx.first.inputs.first.script = old_script

      b = blockchain.chain['main']['8'][3]
      old_mrkl_root = b.mrkl_root
      b.instance_eval{ @mrkl_root = "A"*32 }
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : hashMerkleRoot mismatch')
      b.instance_eval{ @mrkl_root = old_mrkl_root }

      b = blockchain.chain['main']['8'][3]
      old_txs = b.tx
      b.tx = blockchain.chain['main']['0'].tx
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : hashMerkleRoot mismatch')
      b.tx = old_txs

      b = blockchain.chain['main']['8'][3]
      old_payload = b.tx.first.payload
      b.tx.first.instance_eval{ @payload = "A"*(Bitcoin::MAX_BLOCK_SIZE+1) }
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : size limits failed')
      b.tx.first.instance_eval{ @payload = old_payload }

      b = blockchain.chain['main']['8'][3]
      old_value = b.tx.first.outputs.first.value
      b.tx.first.outputs.first.value = Bitcoin.network[:max_money] + 1
      expect {
        processor.process_block(b, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : txout.nValue too high')
      b.tx.first.instance_eval{ @payload = old_payload }
      b.tx.first.outputs.first.value = old_value

      expect {
        processor.process_block(blockchain.chain['main']['8'][4], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : vout empty')
      expect {
        processor.process_block(blockchain.chain['main']['8'][5], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckTransaction() : vin empty')
      expect {
        processor.process_block(blockchain.chain['main']['8'][6], raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'CheckBlock() : out-of-bounds signature operations count')
    end

    # see comment at the top of spec/fixtures/builders/reorg_chain_1.rb for details.
    it 'processes reorg chain 1' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("reorg_chain_1.json")
      blockchain.blocks.each{|block|
        processor.process_block(block, raise_errors=true)
      }

      # 1: basic sanity checks

      expect(Toshi::Models::Block.count).to eq(13) # 10 main blocks, 2 side chain blocks, 1 orphan
      expect(Toshi::Models::Block.head.height).to eq(9) # 10 main blocks
      expect(Toshi::Models::Block.max_height).to eq(9) # sanity check
      expect(Toshi::Models::Transaction.count).to eq(15) # 13 coinbases + 1 tx from height 7 + 1 tx from height 8
      expect(Toshi::Models::Address.count).to eq(15) # 13 coinbase outputs + 2 other parties involved in 2 other txs

      # 2: walk back from tip and verify the main chain is what we expect

      wlkr = Toshi::Models::Block.head
      expect(wlkr.branch_name).to eq('main')
      while wlkr.height >= 0 do
        expect(wlkr.hsh).to eq(blockchain.chain['main'][wlkr.height.to_s].hash)
        expect(wlkr.branch_name).to eq('main')
        break if wlkr.height == 0
        wlkr = wlkr.previous
      end

      # 3: verify we see the expected transactions in the expected blocks

      # block height 7
      blk_hash = blockchain.chain['main']['7'].hash
      expect(Toshi::Models::Block.where(hsh: blk_hash).first.height).to eq(7)

      # check tx 0 (coinbase) for block height 7
      txn_hash = blockchain.chain['main']['7'].tx[0].hash
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # check tx 1 for block height 7
      txn_hash = blockchain.chain['main']['7'].tx[1].hash
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)

      # block height 8
      blk_hash = blockchain.chain['main']['8'].hash
      expect(Toshi::Models::Block.where(hsh: blk_hash).first.height).to eq(8)

      # check tx 0 (coinbase) for block height 8
      txn_hash = blockchain.chain['main']['8'].tx[0].hash
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # check tx 1 for block height 8
      txn_hash = blockchain.chain['main']['8'].tx[1].hash
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)

      # 4: confirm expected balances

      # first recipient, should have nothing (originally he had half of a coinbase reward in block height 7)
      address = blockchain.address_from_label('first spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
      output = Toshi::Models::Address.where(address: address).first.spent_outputs.first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['main']['7'].tx[1].hash)
      expect(output.position).to eq(0)

      # second recipient, should have coinbase reward (originally he only had half)
      address = blockchain.address_from_label('second spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(2)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.order(:output_id).first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['main']['7'].tx[1].hash)
      expect(output.position).to eq(1)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.order(:output_id).last
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['main']['8'].tx[1].hash)
      expect(output.position).to eq(0)
    end

    # test handling of reorg resulting from a missing orphan parent being found.
    it 'processes reorg chain 2' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("reorg_chain_2.json")
      blockchain.blocks.each{|block|
        processor.process_block(block, raise_errors=true)
      }

      # 1: basic sanity checks

      expect(Toshi::Models::Block.count).to eq(9)
      expect(Toshi::Models::Block.head.height).to eq(5) # 6 main blocks
      expect(Toshi::Models::Block.max_height).to eq(5) # sanity check
      expect(Toshi::Models::Transaction.count).to eq(11) # 9 coinbases + 2 other txs to 2 parties each
      expect(Toshi::Models::Address.count).to eq(13) # 9 coinbase outputs + 4 other parties

      # 2: walk back from tip and verify the main chain is what we expect

      count = 0
      wlkr = Toshi::Models::Block.head
      expect(wlkr.branch_name).to eq('main')
      while wlkr.height >= 0 do
        if wlkr.height > 1
          expect(wlkr.hsh).to eq(blockchain.chain['orphan'][wlkr.height.to_s].hash)
        else
          expect(wlkr.hsh).to eq(blockchain.chain['main'][wlkr.height.to_s].hash)
        end
        expect(wlkr.branch_name).to eq('main')
        count += 1
        break if wlkr.height == 0
        wlkr = wlkr.previous
      end

      expect(count).to eq(Toshi::Models::Block.head.height + 1)

      # check tx 1 at block height 4 (was main chain now side chain)
      blk_hash = blockchain.chain['main']['4'].hash
      txn_hash = blockchain.chain['main']['4'].tx[1].hash
      # Transaction::block only returns main chain blocks
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block).to be_nil
      # we should still see the now side chain block in "blocks"
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.count).to eq(1)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.first.hsh).to eq(blk_hash)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.first.branch_name).to eq('side')
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # check tx 1 at orphan block height 5 (now on main chain)
      blk_hash = blockchain.chain['orphan']['5'].hash
      txn_hash = blockchain.chain['orphan']['5'].tx[1].hash
      # the below also tests that it's on the main chain.
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.first.branch_name).to eq('main')
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # confirm expected balances

      # look for the deduction from the coinbase output in block 1
      tx = blockchain.chain['main']['1'].tx[0]
      tx_hash = tx.hash
      address = Bitcoin::Script.new(tx.outputs[0].script).get_address
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.transaction.hsh).to eq(tx_hash)

      # first recipient, should have nothing (originally he had half of a coinbase reward in block height 4 pre-reorg)
      address = blockchain.address_from_label('first spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      # look for the original output
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::SIDE_BRANCH)

      # second recipient, should have nothing (originally he had half of a coinbase reward in block height 4 pre-reorg)
      address = blockchain.address_from_label('second spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      # look for the original output
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::SIDE_BRANCH)

      # third recipient, should have half of a coinbase
      address = blockchain.address_from_label('third spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::MAIN_BRANCH)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['orphan']['5'].tx[1].hash)
      expect(output.position).to eq(0)

      # fourth recipient, should have half of a coinbase
      address = blockchain.address_from_label('fourth spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::MAIN_BRANCH)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['orphan']['5'].tx[1].hash)
      expect(output.position).to eq(1)
    end

    # test handling of reorg resulting from a missing orphan parent being found.
    it 'processes reorg chain 3' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("reorg_chain_3.json")
      blockchain.blocks.each{|block|
        processor.process_block(block, raise_errors=true)
      }

      # 1: basic sanity checks

      expect(Toshi::Models::Block.count).to eq(9)
      expect(Toshi::Models::Block.head.height).to eq(5) # 6 main blocks
      expect(Toshi::Models::Block.max_height).to eq(5) # sanity check
      expect(Toshi::Models::Transaction.count).to eq(10) # 9 coinbases + 1 other tx to 2 parties each
      expect(Toshi::Models::Address.count).to eq(11) # 9 coinbase outputs + 2 other parties

      # 2: walk back from tip and verify the main chain is what we expect

      count = 0
      wlkr = Toshi::Models::Block.head
      expect(wlkr.branch_name).to eq('main')
      while wlkr.height >= 0 do
        if wlkr.height > 1
          expect(wlkr.hsh).to eq(blockchain.chain['orphan'][wlkr.height.to_s].hash)
        else
          expect(wlkr.hsh).to eq(blockchain.chain['main'][wlkr.height.to_s].hash)
        end
        expect(wlkr.branch_name).to eq('main')
        count += 1
        break if wlkr.height == 0
        wlkr = wlkr.previous
      end

      expect(count).to eq(Toshi::Models::Block.head.height + 1)

      # check tx 1 is at orphan height 5 (now on main chain)
      blk_hash = blockchain.chain['orphan']['5'].hash
      txn_hash = blockchain.chain['main']['4'].tx[1].hash # was originally here
      expect(txn_hash).to eq(blockchain.chain['main']['4'].tx[1].hash) # make sure they're the same

      # Transaction::block only returns main chain blocks
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)

      # we should still see the now side chain block in the transaction's "blocks"
      blk_hash = blockchain.chain['main']['4'].hash
      blk_hashes = Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.map{|b| b.hsh}
      expect(blk_hashes).to include(blk_hash)
      old_blk = Toshi::Models::Block.where(hsh: blk_hash).first
      expect(old_blk.branch_name).to eq('side')
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.blocks.count).to eq(2)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # check tx 1 at orphan block height 5 (now on main chain)
      blk_hash = blockchain.chain['orphan']['5'].hash
      txn_hash = blockchain.chain['orphan']['5'].tx[1].hash

      # the below also tests that it's on the main chain.
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.hsh).to eq(blk_hash)
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.block.branch_name).to eq('main')
      expect(Toshi::Models::Transaction.where(hsh: txn_hash).first.total_out_value).to eq(COINBASE_REWARD)

      # confirm expected balances

      # look for the deduction from the coinbase output in block 1
      tx = blockchain.chain['main']['1'].tx[0]
      tx_hash = tx.hash
      address = Bitcoin::Script.new(tx.outputs[0].script).get_address
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.transaction.hsh).to eq(tx_hash)

      # first recipient, should have half a coinbase reward
      address = blockchain.address_from_label('first spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::MAIN_BRANCH)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['orphan']['5'].tx[1].hash)
      expect(output.position).to eq(0)

      # second recipient, should have half a coinbase reward
      address = blockchain.address_from_label('second spend to')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.outputs.first.branch).to eq(Toshi::Models::Block::MAIN_BRANCH)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.first
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['orphan']['5'].tx[1].hash)
      expect(output.position).to eq(1)
    end

    # https://bitcointalk.org/index.php?topic=46370.msg577556#msg577556
    it "processes etotheipi's reorg chain" do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new
      blockchain.load_from_json("reorg_etotheipi_chain.json")

      # process blocks 0-4
      stop_at = 0
      blockchain.blocks.each{|block|
        processor.process_block(block, raise_errors=true)
        break if stop_at == 4
        stop_at += 1
      }

      # sanity checks
      expect(Toshi::Models::Block.count).to eq(5)
      expect(Toshi::Models::Block.head.height).to eq(4)
      expect(Toshi::Models::Block.max_height).to eq(4)
      expect(Toshi::Models::Transaction.count).to eq(9)
      expect(Toshi::Models::Address.count).to eq(4) # A, B, C, D
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::TIP_POOL).count).to eq(9)

      # confirm expected balances at this phase
      balances = { A: 100, B: 0, C: 50, D: 100 }
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:A] * 10**8)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:B] * 10**8)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:C] * 10**8)
      address = blockchain.address_from_label('D')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:D] * 10**8)

      # look at additional fields at this phase
      i = 0
      while i <= stop_at do
        bitcoin_block = blockchain.blocks[i]
        block = Toshi::Models::Block.where(hsh: bitcoin_block.hash).first
        expect(block.transactions_count).to eq(bitcoin_block.tx.size)
        if i < 2 # coinbase only txs
          expect(block.total_in_value).to eq(0)
          expect(block.total_out_value).to eq(COINBASE_REWARD)
        else
          expect(block.total_in_value).to eq(COINBASE_REWARD)
          expect(block.total_out_value).to eq(COINBASE_REWARD*2)
        end
        i += 1
      end

      # continue processing blocks 3A - 5A
      start_at = stop_at + 1
      blockchain.blocks.slice(start_at, blockchain.blocks.length-start_at).each{|block|
        processor.process_block(block, raise_errors=true)
      }

      # sanity checks
      expect(Toshi::Models::Block.count).to eq(8)
      expect(Toshi::Models::Block.head.height).to eq(5)
      expect(Toshi::Models::Block.max_height).to eq(5)
      expect(Toshi::Models::Transaction.count).to eq(12)
      expect(Toshi::Models::Address.count).to eq(4) # A, B, C, D
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::TIP_POOL).count).to eq(10)
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::CONFLICT_POOL).count).to eq(1) # one rejected double-spend
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::BLOCK_POOL).count).to eq(1) # coinbase from block 3
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(0)

      # make sure the expected double-spend is marked as a conflict
      double_spend_tx = blockchain.chain['main']['3'].tx[2]
      expect(Toshi::Models::Transaction.where(hsh: double_spend_tx.hash).first.pool).to eq(Toshi::Models::Transaction::CONFLICT_POOL)

      # walk back from tip and verify the main chain ends up as what we expect
      count = 0
      wlkr = Toshi::Models::Block.head
      expect(wlkr.branch_name).to eq('main')
      while wlkr.height >= 0 do
        if wlkr.height > 2
          expect(wlkr.hsh).to eq(blockchain.chain['side'][wlkr.height.to_s].hash)
        else
          expect(wlkr.hsh).to eq(blockchain.chain['main'][wlkr.height.to_s].hash)
        end
        expect(wlkr.branch_name).to eq('main')
        count += 1
        break if wlkr.height == 0
        wlkr = wlkr.previous
      end
      expect(count).to eq(Toshi::Models::Block.head.height + 1)

      # confirm final expected balances
      balances = { A: 150, B: 10, C: 0, D: 140 }
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:A] * 10**8)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:B] * 10**8)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:C] * 10**8)
      address = blockchain.address_from_label('D')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:D] * 10**8)

      # look at additional fields at this phase
      while i < blockchain.blocks.size do
        bitcoin_block = blockchain.blocks[i]
        block = Toshi::Models::Block.where(hsh: bitcoin_block.hash).first
        expect(block.transactions_count).to eq(bitcoin_block.tx.size)
        if i == 6 # coinbase only tx
          expect(block.total_in_value).to eq(0)
          expect(block.total_out_value).to eq(COINBASE_REWARD)
        else
          expect(block.total_in_value).to eq(COINBASE_REWARD)
          expect(block.total_out_value).to eq(COINBASE_REWARD*2)
        end
        i += 1
      end
    end

    it 'verifies we reject loose coinbases and unconfirmed non-standard txs' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new
      blockchain.set_network_rules(100, :bitcoin) # maturity and network

      # no loose coinbase txs
      cb_tx = blockchain.build_coinbase_tx(0)
      expect {
        processor.process_transaction(cb_tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : coinbase as individual tx')

      # invalid tx version
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0], -1)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: version')

      tx = build_nonstandard_tx(blockchain, [cb_tx], [0], Toshi::CURRENT_TX_VERSION + 1)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: version')

      # non-final tx
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0], Toshi::CURRENT_TX_VERSION, Time.now.to_i + 2*60*60)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: non-final')

      # tx-size
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.in[0].script_sig = [Bitcoin::Script::OP_PUSHDATA4, 100000].pack("CV") + 'A' * 100000;
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: tx-size')

      # scriptsig-size
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.in[0].script_sig = 'A' * 1651
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-size')

      # scriptsig-not-pushonly
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.in[0].script_sig = tx.out[0].pk_script
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-not-pushonly')

      # scriptsig-non-canonical-push
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.in[0].script_sig = "\x01\x10"
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-non-canonical-push')
      tx.in[0].script_sig = [Bitcoin::Script::OP_PUSHDATA1, 75].pack("CC") + 'A' * 75
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-non-canonical-push')
      tx.in[0].script_sig = [Bitcoin::Script::OP_PUSHDATA2, 255].pack("Cv") + 'A' * 255
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-non-canonical-push')
      tx.in[0].script_sig = [Bitcoin::Script::OP_PUSHDATA4, 1645].pack("CV") + 'A' * 1645
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptsig-non-canonical-push')

      # scriptpubkey
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.out[0].pk_script = Bitcoin::Script.from_string('OP_XOR').to_payload
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: scriptpubkey')

      # multi-op-return
      cb_tx2 = blockchain.build_coinbase_tx(0)
      tx = build_nonstandard_tx(blockchain, [cb_tx, cb_tx2], [0, 0])
      tx.out[0].pk_script = Bitcoin::Script.from_string('OP_RETURN d34db33f').to_payload
      tx.out[1].pk_script = Bitcoin::Script.from_string('OP_RETURN 0b4df00d').to_payload
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: multi-op-return')

      # dust
      tx = build_nonstandard_tx(blockchain, [cb_tx], [0])
      tx.out[0].value = 2 * tx.out[0].to_payload.bytesize
      tx.parse_data_from_io(tx.to_payload)
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : nonstandard transaction: dust')

      # this one should be fine - standard tx w/4 inputs + 4 outputs
      # it will still fail due to missing inputs because the parent txs haven't been accepted.
      txs = []
      4.times{ txs << blockchain.build_coinbase_tx(0) }
      tx = build_nonstandard_tx(blockchain, txs, Array.new(4, 0))
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : transaction missing inputs')
    end

    it 'verifies we reject unconfirmed transactions not already in memory pool with missing or already spent inputs' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      # process simple chain to give us a couple confirmed outputs.
      blockchain.load_from_json("simple_chain_1.json")
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
      }

      # first add a valid unconfirmed transaction
      prev_tx = blockchain.chain['main']['7'].tx[1]
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      expect(processor.process_transaction(tx, raise_errors=false)).to eq(true)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(1)

      # already in memory pool
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : already in the memory pool')

      # already spent in the memory pool
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : already spent in the memory pool')

      # inputs missing
      prev_tx = blockchain.build_coinbase_tx(0)
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : transaction missing inputs')

      # inputs already spent
      prev_tx = blockchain.chain['main']['1'].tx[0]
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      expect {
        processor.process_transaction(tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : inputs already spent')
    end

    it 'verifies we reject unconfirmed transactions with non-standard inputs' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      # (1) make sure a 2-of-2 standard multisig scriptSig is considered standard

      prev_tx = blockchain.build_coinbase_tx(0)
      key = blockchain.new_key
      key2 = blockchain.new_key
      pk_script = Bitcoin::Script.to_multisig_script(2, key.pub, key2.pub)
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0], Toshi::CURRENT_TX_VERSION, lock_time=nil, pk_script)

      # inject it directly into the db for testing
      Toshi::Models::Transaction.create_from_tx(tx,
                                                Toshi::Models::Transaction::BLOCK_POOL,
                                                Toshi::Models::Block::ORPHAN_BRANCH)

      # try to redeem it
      tx = build_nonstandard_tx(blockchain, [tx], [0])
      expect(processor.are_inputs_standard?(tx, for_test=true)).to eq(true)

      # (2) make sure a pay-to-pubkey p2sh scriptSig is considered standard

      prev_tx = blockchain.build_coinbase_tx(0)
      pk_script = blockchain.new_p2sh(1, key)
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0], Toshi::CURRENT_TX_VERSION, lock_time=nil, pk_script)

      # inject it directly into the db for testing
      Toshi::Models::Transaction.create_from_tx(tx,
                                                Toshi::Models::Transaction::BLOCK_POOL,
                                                Toshi::Models::Block::ORPHAN_BRANCH)

      # try to redeem it
      tx = build_nonstandard_tx(blockchain, [tx], [0])
      expect(processor.are_inputs_standard?(tx, for_test=true)).to eq(true)

      # (3) make sure a 2-of-2 multisig p2sh scriptSig is considered standard

      prev_tx = blockchain.build_coinbase_tx(0)
      pk_script = blockchain.new_p2sh(2, key, key2)
      tx = build_nonstandard_tx(blockchain, [prev_tx], [0], Toshi::CURRENT_TX_VERSION, lock_time=nil, pk_script)

      # inject it directly into the db for testing
      Toshi::Models::Transaction.create_from_tx(tx,
                                                Toshi::Models::Transaction::BLOCK_POOL,
                                                Toshi::Models::Block::ORPHAN_BRANCH)

      # try to redeem it
      tx = build_nonstandard_tx(blockchain, [tx], [0])
      expect(processor.are_inputs_standard?(tx, for_test=true)).to eq(true)
    end

    it 'verifies we properly detect and handle memory pool conflicts when connecting a block' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      # process simple chain to give us a some confirmed outputs.
      blockchain.load_from_json("simple_chain_1.json")
      blockchain.chain['main'].each{|height, block|
        break if height.to_i == 7 # don't process the last block yet
        processor.process_block(block, raise_errors=true)
      }

      # first add a valid unconfirmed transaction
      prev_tx = blockchain.chain['main']['1'].tx[0]
      conflict_tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      expect(processor.process_transaction(conflict_tx, raise_errors=false)).to eq(true)

      # test that we recursively remove dependent conflicts

      # (1) create a child tx spending the unconfirmed output above
      child_conflict_tx = build_nonstandard_tx(blockchain, [conflict_tx], [0])
      expect(processor.process_transaction(child_conflict_tx, raise_errors=false)).to eq(true)
      # (2) create a child tx spending the unconfirmed output of the other child
      child_conflict_tx2 = build_nonstandard_tx(blockchain, [child_conflict_tx], [0])
      expect(processor.process_transaction(child_conflict_tx2, raise_errors=false)).to eq(true)

      # verify they're in the memory pool
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(3)
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: conflict_tx.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::MEMORY_POOL)
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: child_conflict_tx.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::MEMORY_POOL)
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: child_conflict_tx2.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::MEMORY_POOL)

      # process the last block to trigger a conflict
      block = blockchain.chain['main']['7']
      processor.process_block(block, raise_errors=true)

      expect(Toshi::Models::Block.count).to eq(8)
      expect(Toshi::Models::Block.max_height).to eq(7)
      expect(Toshi::Models::Transaction.count).to eq(9) # same as the simple chain test
      expect(Toshi::Models::UnconfirmedTransaction.count).to eq(3) # but +3 unconfirmeds
      expect(Toshi::Models::Address.count).to eq(10) # same as the simple chain test
      expect(Toshi::Models::UnconfirmedAddress.count).to eq(4) # but +4 unconfirmeds

      # look for the tx to 2 unique addresses in block 7
      tx_hash = blockchain.chain['main']['7'].tx[1].hash

      address = blockchain.address_from_label('first recipient')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(2500000000)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.position).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.transaction.hsh).to eq(tx_hash)

      address = blockchain.address_from_label('second recipient')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(2500000000)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.position).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.first.transaction.hsh).to eq(tx_hash)

      # look for the deduction from the coinbase output in block 1
      tx = blockchain.chain['main']['1'].tx[0]
      tx_hash = tx.hash
      address = Bitcoin::Script.new(tx.outputs[0].script).get_address
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.hsh).to eq(tx_hash)
      expect(Toshi::Models::Address.where(address: address).first.spent_outputs.first.transaction.hsh).to eq(tx_hash)

      # verify number of txs per pool
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(0)
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::TIP_POOL).count).to eq(Toshi::Models::Transaction.count)
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::BLOCK_POOL).count).to eq(0)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::CONFLICT_POOL).count).to eq(3)

      # verify we see the proper conflicted txs
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: conflict_tx.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::CONFLICT_POOL)
      address = Bitcoin::Script.new(conflict_tx.outputs[0].script).get_address
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(0) # make sure it doesn't count toward their balance
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: child_conflict_tx.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::CONFLICT_POOL)
      expect(Toshi::Models::UnconfirmedTransaction.where(hsh: child_conflict_tx2.hash).first.pool).to eq(Toshi::Models::UnconfirmedTransaction::CONFLICT_POOL)
    end

    it 'verifies we properly handle orphan transactions' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      # process simple chain to give us a some confirmed outputs.
      blockchain.load_from_json("simple_chain_1.json")
      last_block, last_height = nil, 0
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
        last_block, last_height = block, height.to_i
      }

      # create the parent but don't process it
      prev_tx = blockchain.chain['main']['7'].tx[1]
      key_A = blockchain.new_key('A')
      parent_tx = build_nonstandard_tx(blockchain, [prev_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_A)

      # create and process a child
      key_B = blockchain.new_key('B')
      orphan_tx = build_nonstandard_tx(blockchain, [parent_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_B)
      expect {
        processor.process_transaction(orphan_tx, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : transaction missing inputs')

      # verify it's in the orphan pool
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::ORPHAN_POOL).count).to eq(1)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(0)

      # create and process a child of the child
      key_C = blockchain.new_key('C')
      orphan_tx2 = build_nonstandard_tx(blockchain, [orphan_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_C)
      expect {
        processor.process_transaction(orphan_tx2, raise_errors=true)
      }.to raise_error(Toshi::Processor::ValidationError, 'AcceptToMemoryPool() : transaction missing inputs')

      # verify it's in the orphan pool
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::ORPHAN_POOL).count).to eq(2)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(0)

      # process the parent
      expect(processor.process_transaction(parent_tx, raise_errors=false)).to eq(true)

      # verify the orphan pool is now cleaned out and all loose txs are in the memory pool
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::ORPHAN_POOL).count).to eq(0)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(3)

      # build another block with the contents of the memory pool
      time = last_block.time+=Bitcoin.network[:next_block_time_target]
      new_block = blockchain.build_next_block(last_block, last_height+1, [parent_tx, orphan_tx, orphan_tx2], time)
      processor.process_block(new_block, raise_errors=true)

      # verify the memory pool is now cleaned out
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::ORPHAN_POOL).count).to eq(0)
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(0)
      expect(Toshi::Models::Transaction.where(pool: Toshi::Models::Transaction::TIP_POOL).count).to eq(13)

      # verify expected balances
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      address = blockchain.address_from_label('first recipient')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
    end

    it 'verify we detect double-spends in the current block' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("simple_chain_1.json")
      last_height, last_block = 0, nil
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
        last_height, last_block = height.to_i, block
      }

      # this blockchain is thoroughly tested in the first processor test.
      # in this test we're just interested in seeing if the processor
      # detects double-spends within the current block so we use a
      # confirmed output from this chain for our test.

      prev_tx = blockchain.chain['main']['7'].tx[1]
      spend_tx = build_nonstandard_tx(blockchain, [prev_tx], [0])
      double_spend_tx = build_nonstandard_tx(blockchain, [prev_tx], [0])

      # build another block with the spend and double-spend attempt
      time = last_block.time+=Bitcoin.network[:next_block_time_target]
      new_block = blockchain.build_next_block(last_block, last_height+1, [spend_tx, double_spend_tx], time)
      message = ''
      begin
        processor.process_block(new_block, raise_errors=true)
      rescue Toshi::Processor::BlockValidationError => ex
        message = ex.message
      end
      expect(message).to eq('ConnectBlock() : inputs missing/spent')

      # once again -- but this time double-spend an output from the same block
      spend_tx = build_nonstandard_tx(blockchain, [prev_tx], [1])
      spend_of_spend_tx = build_nonstandard_tx(blockchain, [spend_tx], [0])
      double_spend_tx = build_nonstandard_tx(blockchain, [spend_tx], [0])

      # build another block with the spend and double-spend attempt
      new_block = blockchain.build_next_block(last_block, last_height+1, [spend_tx, spend_of_spend_tx, double_spend_tx], time)
      message = ''
      begin
        processor.process_block(new_block, raise_errors=true)
      rescue Toshi::Processor::BlockValidationError => ex
        message = ex.message
      end
      expect(message).to eq('ConnectBlock() : inputs missing/spent')
    end

    it 'verify correct balances when spending from the current block' do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("simple_chain_1.json")
      last_height, last_block = 0, nil
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
        last_height, last_block = height.to_i, block
      }

      # this blockchain is thoroughly tested in the first processor test.
      # we process it to generate some confirmed outputs.

      prev_tx = blockchain.chain['main']['7'].tx[1]

      key_A = blockchain.new_key('A')
      spend_tx = build_nonstandard_tx(blockchain, [prev_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_A)

      key_B = blockchain.new_key('B')
      spend_tx2 = build_nonstandard_tx(blockchain, [spend_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_B)

      key_C = blockchain.new_key('C')
      spend_tx3 = build_nonstandard_tx(blockchain, [spend_tx2], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_C)

      key_D = blockchain.new_key('D')
      spend_tx4 = build_nonstandard_tx(blockchain, [prev_tx], [1], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_D)

      # build another block with the new txs
      time = last_block.time+=Bitcoin.network[:next_block_time_target]
      new_block = blockchain.build_next_block(last_block, last_height+1, [spend_tx, spend_tx2, spend_tx3, spend_tx4], time)
      processor.process_block(new_block, raise_errors=true)

      # verify expected balances
      address = Bitcoin::Script.new(prev_tx.outputs[0].script).get_address
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = Bitcoin::Script.new(prev_tx.outputs[1].script).get_address
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      address = blockchain.address_from_label('D')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
    end

    it "verifies we don't unmark spent outputs due to connecting a block" do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new

      blockchain.load_from_json("simple_chain_1.json")
      last_height, last_block = 0, nil
      blockchain.chain['main'].each{|height, block|
        processor.process_block(block, raise_errors=true)
        last_height, last_block = height.to_i, block
      }

      # this blockchain is thoroughly tested in the first processor test.
      # we process it to generate some confirmed outputs.

      prev_tx = blockchain.chain['main']['7'].tx[1]

      # send the coins to A
      key_A = blockchain.new_key('A')
      spend_tx = build_nonstandard_tx(blockchain, [prev_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_A)
      expect(processor.process_transaction(spend_tx, raise_errors=true)).to eq(true)

      # should reflect in A's unconfirmed balance
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.unspent_outputs.count).to eq(1)

      # send the coins to B
      key_B = blockchain.new_key('B')
      spend_tx2 = build_nonstandard_tx(blockchain, [spend_tx], [0], ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, key_B)
      expect(processor.process_transaction(spend_tx2, raise_errors=true)).to eq(true)

      # should reflect in their unconfirmed balances
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(0)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(COINBASE_REWARD/2)

      # build another block with the tx to A
      time = last_block.time+=Bitcoin.network[:next_block_time_target]
      new_block = blockchain.build_next_block(last_block, last_height+1, [spend_tx], time)
      expect(processor.process_block(new_block, raise_errors=true)).to eq(true)

      # still no unspent output in mempool
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.unspent_outputs.count).to eq(0)
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(0)

      # it's still unspent in the blockchain's view though
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(COINBASE_REWARD/2)

      # he still has his unspent output in the mempool
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(COINBASE_REWARD/2)
    end

    it "verifies expected state when disconnecting and not reconnecting txs" do
      processor = Toshi::Processor.new
      blockchain = Blockchain.new
      blockchain.load_from_json("reorg_with_mempool.json")

      # process blocks 0-3
      stop_at = 0
      blockchain.blocks.each{|block|
        processor.process_block(block, raise_errors=true)
        break if stop_at == 3
        stop_at += 1
      }

      # confirm expected balances at this phase
      balances = { A: 60, B: 60, C: 80 }
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:A] * 10**8)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:B] * 10**8)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:C] * 10**8)

      # continue processing blocks 3A - 4A
      start_at = stop_at + 1
      blockchain.blocks.slice(start_at, blockchain.blocks.length-start_at).each{|block|
        processor.process_block(block, raise_errors=true)
      }

      # 2 now loose txs should be in the mempool. 1 spends the other.
      expect(Toshi::Models::UnconfirmedTransaction.where(pool: Toshi::Models::UnconfirmedTransaction::MEMORY_POOL).count).to eq(2)

      # shouldn't end up with any spent outputs on a non-main branch
      expect(Toshi::Models::Output.where(spent: true).exclude(branch: Toshi::Models::Block::MAIN_BRANCH).count).to eq(0)

      # final expected confirmed balances
      balances = { A: 100, B: 100, C: 50 }
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:A] * 10**8)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:B] * 10**8)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::Address.where(address: address).first.unspent_outputs.count).to eq(1)
      expect(Toshi::Models::Address.where(address: address).first.balance).to eq(balances[:C] * 10**8)

      # final unconfirmed balances
      balances = { A: 110, B: 60, C: 80 }
      address = blockchain.address_from_label('A')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(balances[:A] * 10**8)
      address = blockchain.address_from_label('B')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(balances[:B] * 10**8)
      address = blockchain.address_from_label('C')
      expect(Toshi::Models::UnconfirmedAddress.where(address: address).first.balance).to eq(balances[:C] * 10**8)
    end
  end
end
