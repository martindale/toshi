#!/usr/bin/env ruby
$:.unshift( File.expand_path("../../lib", __FILE__) )
require 'bitcoin'
require_relative '../../support/blockchain'

blockchain = Blockchain.new

time = blockchain.time
height = blockchain.next_height(:main)
b = blockchain.build_next_block(nil, height, [], time)
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

6.times{
  height = blockchain.next_height(:main)
  b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target])
  blockchain.chain[:main][height] = b
}

# for block 7 redeem the output from 2nd block and send to two new addresses
prev_tx, prev_tx_output_index = blockchain.chain[:main][1].tx.first, 0
value = prev_tx.outputs[prev_tx_output_index].value
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

min_fee = 50_000
next_fees = 0
key = blockchain.new_key('first recipient')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address((value/2)-min_fee, key.addr)
next_fees += min_fee

key = blockchain.new_key('second recipient')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address((value/2)-min_fee, key.addr)
next_fees += min_fee

input_index = 0
privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
signature = key.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)

new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)
raise "failed to generate testbox tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [new_tx], time+=Bitcoin.network[:next_block_time_target], next_fees)
main_b = b
blockchain.chain[:main][height] = b
last_height = height

# build tmp side chain
b = blockchain.build_next_block(b, last_height, [], time+10)
blockchain.chain[:side][last_height] = b
b = blockchain.build_next_block(b, last_height+1, [], time+10+Bitcoin.network[:next_block_time_target])
blockchain.chain[:side][last_height+1] = b

# build tmp orphan block
b = blockchain.build_next_block(b, last_height+1, [], time+10)
b = blockchain.build_next_block(b, last_height+2, [], time+10+Bitcoin.network[:next_block_time_target])
blockchain.chain[:orphan][last_height+2] = b

# for the 9th block redeem the output from 7th block 2nd tx and send it to new address
prev_tx, prev_tx_output_index = blockchain.chain[:main][7].tx[1], 0
value = prev_tx.outputs[prev_tx_output_index].value
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

min_fee = 50_000
next_fees = 0

privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index+1].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value-min_fee, key.addr)
next_fees += min_fee

input_index = 0
privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
signature = key.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, [key.pub].pack("H*"))

new_tx = Bitcoin::Protocol::Tx.new( new_tx.to_payload )
raise "failed to generate testbox tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

height = blockchain.next_height(:main)
b = blockchain.build_next_block(main_b, height, [new_tx], time+=Bitcoin.network[:next_block_time_target], next_fees)
blockchain.chain[:main][height] = b

next_fees = 0
height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target], next_fees)
blockchain.chain[:main][height] = b

blockchain.pretty_print_json
