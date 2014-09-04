#!/usr/bin/env ruby
#
# Basic blockchain re-org test:
#
# 0 - ... - 6 - 7          ... - 8 (side for now) - 9 (becomes main again)
#            \
#              -- 7 (side) - 8 (side, becomes main tip briefly)
#
#                      ... - 9 (orphan, stays orphan)
#
# Order of processing:
#
# 0 - 7 (main), 7 (side), 8 (side), 9 (orphan), 8 (main), 9 (main)
#
# We expect to see 9 (main) at the tip when we're done.
#
$:.unshift( File.expand_path("../../lib", __FILE__) )

require 'bitcoin'
require_relative '../../support/blockchain'

# build a blockchain
blockchain = Blockchain.new

# genesis (block 0)
time = blockchain.time
height = blockchain.next_height(:main)
block = blockchain.build_next_block(nil, height, [], time)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

# main blocks 1-6
6.times{
  height = blockchain.next_height(:main)
  block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target])
  blockchain.chain[:main][height] = block
  blockchain.add_block_in_sequence(block)
}

# save fork location (block 6)
fork_block = block
fork_height = height

# for main block 7 redeem the output from block 1 and send to two new addresses

prev_tx, prev_tx_output_index = blockchain.chain[:main][1].tx.first, 0
value = prev_tx.outputs[prev_tx_output_index].value
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

key = blockchain.new_key("first spend to")
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value/2, key.addr)

key = blockchain.new_key("second spend to")
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value/2, key.addr)

input_index = 0
privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
signature = key.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)

new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

# main block 7
height = blockchain.next_height(:main)
block = blockchain.build_next_block(block, height, [new_tx], time+=Bitcoin.network[:next_block_time_target])
main_block = block
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)
last_height = height # save last height for main chain

# build side chain

# side chain block 7
block = blockchain.build_next_block(fork_block, fork_height+1, [], time+10)
blockchain.chain[:side][fork_height+1] = block
blockchain.add_block_in_sequence(block)

# side chain block 8
block = blockchain.build_next_block(block, fork_height+2, [], time+10+Bitcoin.network[:next_block_time_target])
blockchain.chain[:side][fork_height+2] = block
blockchain.add_block_in_sequence(block)

# build orphan chain

# create the parent which we'll omit from the sequence
block = blockchain.build_next_block(block, last_height+1, [], time+10)

# orphan block 9
block = blockchain.build_next_block(block, last_height+2, [], time+10+Bitcoin.network[:next_block_time_target])
blockchain.chain[:orphan][last_height+2] = block
blockchain.add_block_in_sequence(block)

# for main block 8 redeem the output from block 7's 2nd tx and send it to a new address
prev_tx, prev_tx_output_index = blockchain.chain[:main][7].tx[1], 0
value = prev_tx.outputs[prev_tx_output_index].value
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index+1].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value, key.addr)

input_index = 0
privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
signature = key.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, [key.pub].pack("H*"))

new_tx = Bitcoin::Protocol::Tx.new( new_tx.to_payload )
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

# main block 8
height = blockchain.next_height(:main)
block = blockchain.build_next_block(main_block, height, [new_tx], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

# main block 9
height = blockchain.next_height(:main)
block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

# dump the blockchain in JSON
blockchain.pretty_print_json
