#!/usr/bin/env ruby
#
# This test was discussed here: https://bitcointalk.org/index.php?topic=46370.msg577556#msg577556
#
# Armory developer 'etotheipi' created this test. It looks good so this is a direct port to rspec.
#
# Blockchain:
#
#     0 - 1 - 2 - 3 - 4
#              \
#               3A - 4A - 5A
#
# Order of processing: 0 - 4, then 3A - 5A
#
# Addresses: A, B, C, D
#
# After blocks 0 - 4 are processed the balances should be:
# {A: 100 | B: 0 | C: 50 | D: 100}
#
# After blocks 3A - 5A are processed the balances should be:
# {A: 150 | B: 10 | C: 0 | D: 140}
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
# - Coinbase goes to B
# - B sends C 10 and 40 back to himself
#
prev_tx, prev_tx_output_index = blockchain.chain[:main][1].tx.first, 0
value = prev_tx.outputs[prev_tx_output_index].value

new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

# 10 BTC to C
key_C = blockchain.new_key('C')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value/5, key_C.addr)

# 40 BTC back to self
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value - (value/5), key_B.addr)

input_index = 0
signature = key_B.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)

new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

height = blockchain.next_height(:main)
block = blockchain.build_next_block(block, height, [new_tx], time+=Bitcoin.network[:next_block_time_target], 0, key_B)
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
# - B sends D 40
# - C sends D 10
#

# B sends 40 to D
prev_tx, prev_tx_output_index = new_tx, 1
value = prev_tx.outputs[prev_tx_output_index].value

new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

key_D = blockchain.new_key('D')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value, key_D.addr)

input_index = 0
signature = key_B.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
pubkey = [key_B.pub].pack("H*")
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, pubkey)
new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

# to be used by block 3A
block_3_dup_tx = new_tx

# C sends 10 to D
prev_tx_output_index = 0
value = prev_tx.outputs[prev_tx_output_index].value

new_tx2 = Bitcoin::Protocol::Tx.new
new_tx2.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)
new_tx2.add_out Bitcoin::Protocol::TxOut.value_to_address(value, key_D.addr)

input_index = 0
signature = key_C.sign(new_tx2.signature_hash_for_input(input_index, prev_tx))
pubkey = [key_C.pub].pack("H*")
new_tx2.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, pubkey)
new_tx2 = Bitcoin::Protocol::Tx.new(new_tx2.to_payload)
raise "failed to generate tx" unless new_tx2.verify_input_signature(input_index, prev_tx) == true

height = 3
block = blockchain.build_next_block(block, height, [new_tx, new_tx2], time+=Bitcoin.network[:next_block_time_target], 0, key_C)
blockchain.chain[:side][height] = block
blockchain.add_block_in_sequence(block)

#
# block 4
#
# - Coinbase goes to A
# - B sends D 50
#

# B sends 50 to D
prev_tx, prev_tx_output_index = blockchain.chain[:main][2].tx.first, 0
value = prev_tx.outputs[prev_tx_output_index].value

new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value, key_D.addr)

input_index = 0
signature = key_B.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)
new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

block_4_dup_tx = new_tx

height = 4
block = blockchain.build_next_block(block, height, [new_tx], time+=Bitcoin.network[:next_block_time_target], 0, key_A)
blockchain.chain[:side][height] = block
blockchain.add_block_in_sequence(block)

#
# block 3A
#
# - Coinbase goes to D
# - B sends D 40 (same tx 0 from block 3)
# - C sends B 10 (double-spend of block 3 tx 1)
#

# B sends 40 to D - already exists as block_3_dup_tx

# C sends 10 to B
prev_tx, prev_tx_output_index = blockchain.chain[:main][2].tx[1], 0
value = prev_tx.outputs[prev_tx_output_index].value

new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value, key_B.addr)

input_index = 0
signature = key_C.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
pubkey = [key_C.pub].pack("H*")
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, pubkey)
new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

height = fork_height+1
block = blockchain.build_next_block(fork_block, height, [block_3_dup_tx, new_tx], time=fork_time, 0, key_D)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

#
# block 4A
#
# Coinbase goes to A
#
height += 1
block = blockchain.build_next_block(block, height, [], time+=Bitcoin.network[:next_block_time_target], 0, key_A)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

#
# block 5A
#
# - Coinbase goes to A
# - B sends D 50 (dup tx from block 4)
#
height += 1
block = blockchain.build_next_block(block, height, [block_4_dup_tx], time+=Bitcoin.network[:next_block_time_target], 0, key_A)
blockchain.chain[:main][height] = block
blockchain.add_block_in_sequence(block)

# dump the blockchain to JSON
blockchain.pretty_print_json
