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
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.all[0]
      expect(output.amount).to eq(COINBASE_REWARD/2)
      expect(output.hsh).to eq(blockchain.chain['main']['7'].tx[1].hash)
      expect(output.position).to eq(1)
      output = Toshi::Models::Address.where(address: address).first.unspent_outputs.all[1]
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

    it 'verifies our version of bitcoin-ruby handles funky scripts it has previously had issues with' do

      # 4d932e00d5e20e31211136651f1665309a11908e438bb4c30799154d26812491
      raw_tx = '0100000002bab3b61c5a7facd63a090addb0a4ea1863ccb0f8d6d8d5c1d7b747b5aa9b17bc01000000fdfe000048304502210089666e61b0486a71f2103414315aa4c418dc65815f8b8bfcfab1037c3c2a66210220428b8162874cfc97e05dee6f901dae03820d11011fa7828ecb8fbca45be2188d01493046022100c6c19d75b6d5c911813b2b64cee07c6338f54bca0395264e53c3b3d8ca8e4f8e022100bbcb8d32960e62f26e3e5bdeca605a8b49f1a42cedd20bad507a1bc23c565faf01ab522103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea21032462c60ebc21f4d38b3c4ccb33be77b57ae72762be12887252db18fd6225befb53aeffffffffb1678d9af66c4b8cde45d0d445749322746ab900e546d3900cf30f436e73428a01000000fd470100483045022100a7af036203a1e6b2e833b0d6b402958d58f9ffaaff4969539f213634f17600ee0220192594a5c60f70e5a97dc48fec06df0d3b17c44850162d3d552c7d8653d159a001483045022072020e687ce937828827e85bc916716a9099a510e7fbd96a2836617afa370108022100ce737ad7b46c249cda2b09cb065ea16078b9a3a31f6fc6b63385f645abfdafdf01493046022100c30c5f6e943a78d502216e019821545b940b940784e83051945d89c92ec245f0022100b5c76266878ee8f29f65401fb0af6ba3941641740d846cb551059c0ad25b798c01ab532103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea21032462c60ebc21f4d38b3c4ccb33be77b57ae72762be12887252db18fd6225befb53aeffffffff0150c300000000000017142c68bb496b123d39920fcfdc206daa08bbe58506b17500000000'

      # first input to the above is output @ index 1 below
      prev_tx = '010000000290c5e425bfba62bd5b294af0414d8fa3ed580c5ca6f351ccc23e360b14ff7f470100000091004730440220739d9ab2c3e7089e7bd311f267a65dc0ea00f49619cb61ec016a5038016ed71202201b88257809b623d471e429787c36e0a9bcd2a058fc0c75fd9c25f905657e3b9e01ab512103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea52aeffffffffdd7f3ce640a2fb04dbe24630aa06e4299fbb1d3fe585fe4f80be4a96b5ff0a0d01000000b400483045022100a28d2ace2f1cb4b2a58d26a5f1a2cc15cdd4cf1c65cee8e4521971c7dc60021c0220476a5ad62bfa7c18f9174d9e5e29bc0062df543e2c336ae2c77507e462bbf95701ab512103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea21032462c60ebc21f4d38b3c4ccb33be77b57ae72762be12887252db18fd6225befb53aeffffffff02e0fd1c00000000001976a9148501106ab5492387998252403d70857acfa1586488ac50c3000000000000171499050637f553f03cc0f82bbfe98dc99f10526311b17500000000'

      # second input is output @ index 1 below
      prev_tx2 = '0100000001bab3b61c5a7facd63a090addb0a4ea1863ccb0f8d6d8d5c1d7b747b5aa9b17bc000000006b483045022056eaab9d21789a762c7aefdf84d90daf35f7d98bc917c83a1ae6fa24d44f2b94022100a8e1d45d4bc51ad3a192b1b9d582a4711971b0e957012a303950b83eda3d306c01210375228faaa97a02433f4f126ba8d5a295b92466608acf8d13740130d5bbf9cdb4ffffffff0240771b00000000001976a914bb05d829af3b31730e69b7eeb83c1c0d21d362eb88ac50c3000000000000171452cf84e83d1dc919ef4ada30c44cf4349ee55af9b17500000000'

      prev_tx = Bitcoin::P::Tx.new([prev_tx].pack("H*"))
      prev_tx2 = Bitcoin::P::Tx.new([prev_tx2].pack("H*"))
      tx = Bitcoin::P::Tx.new([raw_tx].pack("H*"))
      expect(tx.verify_input_signature(0, prev_tx.outputs[1].pk_script)).to eq(true)
      expect(tx.verify_input_signature(1, prev_tx2.outputs[1].pk_script)).to eq(true)

      # bc179baab547b7d7c1d5d8d6f8b0cc6318eaa4b0dd0a093ad6ac7f5a1cb6b3ba
      raw_tx = '010000000290c5e425bfba62bd5b294af0414d8fa3ed580c5ca6f351ccc23e360b14ff7f470100000091004730440220739d9ab2c3e7089e7bd311f267a65dc0ea00f49619cb61ec016a5038016ed71202201b88257809b623d471e429787c36e0a9bcd2a058fc0c75fd9c25f905657e3b9e01ab512103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea52aeffffffffdd7f3ce640a2fb04dbe24630aa06e4299fbb1d3fe585fe4f80be4a96b5ff0a0d01000000b400483045022100a28d2ace2f1cb4b2a58d26a5f1a2cc15cdd4cf1c65cee8e4521971c7dc60021c0220476a5ad62bfa7c18f9174d9e5e29bc0062df543e2c336ae2c77507e462bbf95701ab512103c86390eb5230237f31de1f02e70ce61e77f6dbfefa7d0e4ed4f6b3f78f85d8ec2103193f28067b502b34cac9eae39f74dba4815e1278bab31516efb29bd8de2c1bea21032462c60ebc21f4d38b3c4ccb33be77b57ae72762be12887252db18fd6225befb53aeffffffff02e0fd1c00000000001976a9148501106ab5492387998252403d70857acfa1586488ac50c3000000000000171499050637f553f03cc0f82bbfe98dc99f10526311b17500000000'

      # first input to the above is output @ index 1 below
      prev_tx = '0100000001eae7c33c5a3ad25316a4a1a0220343693077d7a35c6d242ed731d9f26c9f8b45010000006b48304502205b910ff27919bb4b81847e17e19848a8148373b5d84856e8a0798395c1a4df6e022100a9300a11b37b52997726dab17851914151bd647ca053d60a013b8e0ad42d1c6e012102b2e1e38d1b15170212a852f68045979d790814a139ed57bffba3763f75e18808ffffffff02b0453c00000000001976a914c39c8d989dfdd7fde0ee80be36113c5abcefcb9c88ac40420f0000000000171464d63d835705618da2111ca3194f22d067187cf2b17500000000'

      # second input is output @ index 1 below
      prev_tx2 = '010000000190c5e425bfba62bd5b294af0414d8fa3ed580c5ca6f351ccc23e360b14ff7f47000000006b4830450220668828280473923647f2fb99450578a18f81e92358d94c933b7033b4370448b8022100cfbce6723163c907b3b86777f0698cc29ea5f89d0fce657a3894afcb1c717da50121033be10bdc7ff38235cf469449147636c4e0e49aacdd0a25af4109cbebd361e0d2ffffffff0220402c00000000001976a9142758fcf332b5df477ec6d877d3b72526b827202b88ac40420f0000000000171451c387bb5c66d1e9d4d054fd96d0844eecf3b664b17500000000'

      prev_tx = Bitcoin::P::Tx.new([prev_tx].pack("H*"))
      prev_tx2 = Bitcoin::P::Tx.new([prev_tx2].pack("H*"))
      tx = Bitcoin::P::Tx.new([raw_tx].pack("H*"))
      expect(tx.verify_input_signature(0, prev_tx.outputs[1].pk_script)).to eq(true)
      expect(tx.verify_input_signature(1, prev_tx2.outputs[1].pk_script)).to eq(true)

      #
      # the 3 below are all the same script styles
      #

      # eb3b82c0884e3efa6d8b0be55b4915eb20be124c9766245bcc7f34fdac32bccb
      raw_tx = '01000000024de8b0c4c2582db95fa6b3567a989b664484c7ad6672c85a3da413773e63fdb8000000006b48304502205b282fbc9b064f3bc823a23edcc0048cbb174754e7aa742e3c9f483ebe02911c022100e4b0b3a117d36cab5a67404dddbf43db7bea3c1530e0fe128ebc15621bd69a3b0121035aa98d5f77cd9a2d88710e6fc66212aff820026f0dad8f32d1f7ce87457dde50ffffffff4de8b0c4c2582db95fa6b3567a989b664484c7ad6672c85a3da413773e63fdb8010000006f004730440220276d6dad3defa37b5f81add3992d510d2f44a317fd85e04f93a1e2daea64660202200f862a0da684249322ceb8ed842fb8c859c0cb94c81e1c5308b4868157a428ee01ab51210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55a51aeffffffff02e0fd1c00000000001976a914380cb3c594de4e7e9b8e18db182987bebb5a4f7088acc0c62d000000000017142a9bc5447d664c1d0141392a842d23dba45c4f13b17500000000'

      prev_tx = '01000000017ea56cd68c74b4cd1a2f478f361b8a67c15a6629d73d95ef21d96ae213eb5b2d010000006a4730440220228e4deb3bc5b47fc526e2a7f5e9434a52616f8353b55dbc820ccb69d5fbded502206a2874f7f84b20015614694fe25c4d76f10e31571f03c240e3e4bbf1f9985be201210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55affffffff0230c11d00000000001976a914709dcb44da534c550dacf4296f75cba1ba3b317788acc0c62d000000000017142a9bc5447d664c1d0141392a842d23dba45c4f13b17500000000'

      prev_tx = Bitcoin::P::Tx.new([prev_tx].pack("H*"))
      tx = Bitcoin::P::Tx.new([raw_tx].pack("H*"))
      tx.inputs.each_with_index do |txin,i|
        # prev outs are from the same tx and in the same order as the inputs to this tx
        expect(tx.verify_input_signature(i, prev_tx.outputs[i].pk_script)).to eq(true)
      end


      # 6d36bc17e947ce00bb6f12f8e7a56a1585c5a36188ffa2b05e10b4743273a74b
      raw_tx = '010000000237b17d763851cd1ab04a424463d413c4ee5cf61304c7fd76977bea7fce075705000000006a473044022002dbe4b5a2fbb521e4dc5fbec75fd960651a2754b03d0871b8c965469be50fa702206d97421fb7ea9359b63e48c2108223284b9a71560bd8182469b9039228d7b3d701210295bf727111acdeab8778284f02b768d1e21acbcbae42090cc49aaa3cc6d19cdaffffffff37b17d763851cd1ab04a424463d413c4ee5cf61304c7fd76977bea7fce0757050100000070004830450220106a3e4ef0b51b764a28872262ffef55846514dacbdcbbdd652c849d395b4384022100e03ae554c3cbb40600d31dd46fc33f25e47bf8525b1fe07282e3b6ecb5f3bb2801ab51210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55a51aeffffffff01003e4900000000001976a9140d7713649f9a0678f4e880b40f86b93289d1bb2788ac00000000'

      prev_tx = '0100000002cbbc32acfd347fcc5b2466974c12be20eb15495be50b8b6dfa3e4e88c0823beb000000006a47304402205e9e74f93f6aa1b095bbe124be0be95aeca52ebe91f214c86febe512b26c827c0220379ee83416df7c2adc753b5eefe61e7aef10ec208b549a249b6006e8009a0e210121031dd6da443782f1099b0ed98060b9ee1b81cd2392e938d23015749625c7dd0470ffffffffcbbc32acfd347fcc5b2466974c12be20eb15495be50b8b6dfa3e4e88c0823beb010000007000483045022013187aed1aeaaca0ca8a7c0e4f6362070208e68a5230c7a3cf65d922da19964802210082ac0719fd2be6c40b550791a96449e6bf1f70ed9492f88e825416c099d36b2601ab51210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55a51aeffffffff02903a1c00000000001976a914f7d46c08dd53bc6bbb52178d60b3fc99a9c1fb8788acc0c62d000000000017142a9bc5447d664c1d0141392a842d23dba45c4f13b17500000000'

      prev_tx = Bitcoin::P::Tx.new([prev_tx].pack("H*"))
      tx = Bitcoin::P::Tx.new([raw_tx].pack("H*"))
      tx.inputs.each_with_index do |txin,i|
        # prev outs are from the same tx and in the same order as the inputs to this tx
        expect(tx.verify_input_signature(i, prev_tx.outputs[i].pk_script)).to eq(true)
      end

      # 055707ce7fea7b9776fdc70413f65ceec413d46344424ab01acd5138767db137
      raw_tx = '0100000002cbbc32acfd347fcc5b2466974c12be20eb15495be50b8b6dfa3e4e88c0823beb000000006a47304402205e9e74f93f6aa1b095bbe124be0be95aeca52ebe91f214c86febe512b26c827c0220379ee83416df7c2adc753b5eefe61e7aef10ec208b549a249b6006e8009a0e210121031dd6da443782f1099b0ed98060b9ee1b81cd2392e938d23015749625c7dd0470ffffffffcbbc32acfd347fcc5b2466974c12be20eb15495be50b8b6dfa3e4e88c0823beb010000007000483045022013187aed1aeaaca0ca8a7c0e4f6362070208e68a5230c7a3cf65d922da19964802210082ac0719fd2be6c40b550791a96449e6bf1f70ed9492f88e825416c099d36b2601ab51210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55a51aeffffffff02903a1c00000000001976a914f7d46c08dd53bc6bbb52178d60b3fc99a9c1fb8788acc0c62d000000000017142a9bc5447d664c1d0141392a842d23dba45c4f13b17500000000'

      prev_tx = '01000000024de8b0c4c2582db95fa6b3567a989b664484c7ad6672c85a3da413773e63fdb8000000006b48304502205b282fbc9b064f3bc823a23edcc0048cbb174754e7aa742e3c9f483ebe02911c022100e4b0b3a117d36cab5a67404dddbf43db7bea3c1530e0fe128ebc15621bd69a3b0121035aa98d5f77cd9a2d88710e6fc66212aff820026f0dad8f32d1f7ce87457dde50ffffffff4de8b0c4c2582db95fa6b3567a989b664484c7ad6672c85a3da413773e63fdb8010000006f004730440220276d6dad3defa37b5f81add3992d510d2f44a317fd85e04f93a1e2daea64660202200f862a0da684249322ceb8ed842fb8c859c0cb94c81e1c5308b4868157a428ee01ab51210232abdc893e7f0631364d7fd01cb33d24da45329a00357b3a7886211ab414d55a51aeffffffff02e0fd1c00000000001976a914380cb3c594de4e7e9b8e18db182987bebb5a4f7088acc0c62d000000000017142a9bc5447d664c1d0141392a842d23dba45c4f13b17500000000'

      prev_tx = Bitcoin::P::Tx.new([prev_tx].pack("H*"))
      tx = Bitcoin::P::Tx.new([raw_tx].pack("H*"))
      tx.inputs.each_with_index do |txin,i|
        # prev outs are from the same tx and in the same order as the inputs to this tx
        expect(tx.verify_input_signature(i, prev_tx.outputs[i].pk_script)).to eq(true)
      end
    end

  end
end
