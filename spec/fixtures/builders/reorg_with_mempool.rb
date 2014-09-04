#!/usr/bin/env ruby
#
# Blockchain:
#
#     0 - 1 - 2 - 3
#              \
#               3A - 4A
#
# Order of processing: 0 - 3, then 3A and 4A
#
# 2 txs from block 3 are left in the mempool and not included in 3A and 4A
# We want to make sure they end up in the memory pool with outputs on main branch.
#
$:.unshift( File.expand_path("../../lib", __FILE__) )

require 'bitcoin'
require_relative '../../support/blockchain'

# build the blockchain
blockchain = Blockchain.new
time = blockchain.time
blockchain.set_network_rules(1) # maturity

#
# genesis (block 0)
#
# Coinbase goes to A
#
height = blockchain.next_height(:main)
key_A = blockchain.new_key('A')
block = blockchain.build_next_block(nil, height, [], time, 0, key_A)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

#
# block 1
#
# Coinbase goes to B
#
height = blockchain.next_height(:main)
key_B = blockchain.new_key('B')
block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target], 0, key_B)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

#
# block 2
#
# Coinbase goes to B
#
height = blockchain.next_height(:main)
block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target], 0, key_B)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

# save the fork point
fork_block = block
fork_height = height
fork_time = time

#
# block 3
#
# - Coinbase goes to C
# - B sends C 40; sends 10 back to self
# - C sends A 10; sends 30 back to self
#

# B sends 40 to C
prev_tx, prev_tx_output_index = blockchain.chain[:main][1].tx.first, 0
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

# 40 to C
key_C = blockchain.new_key('C')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(40*(10**8), key_C.addr)

# 10 to back self
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(10*(10**8), key_B.addr)

input_index = 0
signature = key_B.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)
new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

# C sends 10 to A
prev_tx, prev_tx_output_index = new_tx, 0
new_tx2 = Bitcoin::Protocol::Tx.new
new_tx2.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

# 10 to A
new_tx2.add_out Bitcoin::Protocol::TxOut.value_to_address(10*(10**8), key_A.addr)

# 30 to back self
new_tx2.add_out Bitcoin::Protocol::TxOut.value_to_address(30*(10**8), key_C.addr)

input_index = 0
signature = key_C.sign(new_tx2.signature_hash_for_input(input_index, prev_tx))
pubkey = [key_C.pub].pack("H*")
new_tx2.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, pubkey)
new_tx2 = Bitcoin::Protocol::Tx.new(new_tx2.to_payload)
raise "failed to generate tx" unless new_tx2.verify_input_signature(input_index, prev_tx) == true

height = blockchain.next_height(:main)
block = blockchain.build_next_block(block, height, [new_tx, new_tx2], time+=Bitcoin.network[:next_block_time_target], 0, key_C)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

#
# block 3A
#
# Coinbase goes to C
#

height = fork_height+1
block = blockchain.build_next_block(fork_block, height, [], time=fork_time, 0, key_C)
blockchain.chain[:side][height] = block
blockchain.add_block_in_sequence(block)

#
# block 4A
#
# Coinbase goes to A
#
height += 1
block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target], 0, key_A)
blockchain.chain[:side][height] = block
blockchain.add_block_in_sequence(block)

# dump the blockchain to JSON
blockchain.pretty_print_json
