#!/usr/bin/env ruby
$:.unshift( File.expand_path("../../lib", __FILE__) )

require 'bitcoin'
require_relative '../../support/blockchain'

blockchain = Blockchain.new

time = blockchain.time
height = blockchain.next_height(:main)
b = blockchain.build_next_block(nil, height, [], time)
blockchain.chain[:main][height] = b
Bitcoin.network[:genesis_hash] = b.hash

6.times{
  height = blockchain.next_height(:main)
  b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target])
  blockchain.chain[:main][height] = b
}

# for the 8th block redeem the output from 2nd block and send to two new addresses
prev_tx, prev_tx_output_index = blockchain.chain[:main][1].tx.first, 0
value = prev_tx.outputs[prev_tx_output_index].value
new_tx = Bitcoin::Protocol::Tx.new
new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_index, 0)

key = blockchain.new_key('first recipient')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value/2, key.addr)

key = blockchain.new_key('second recipient')
new_tx.add_out Bitcoin::Protocol::TxOut.value_to_address(value/2, key.addr)

input_index = 0
privkey = blockchain.wallet[ Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_index].script).get_address ][:privkey]
key = Bitcoin::Key.from_base58(privkey)
signature = key.sign(new_tx.signature_hash_for_input(input_index, prev_tx))
new_tx.in[input_index].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)

new_tx = Bitcoin::Protocol::Tx.new( new_tx.to_payload )
raise "failed to generate testbox tx" unless new_tx.verify_input_signature(input_index, prev_tx) == true

height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [new_tx], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = b

blockchain.pretty_print_json
