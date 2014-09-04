#!/usr/bin/env ruby
#
# Another ressurrected orphan blockchain re-org test:
#
# 0 - 1 - 2 - 3 - 4      main chain
#
#           - 3 - 4 - 5  oprhan chain
#
# We're in the state above when orphan block 2 shows up with main chain 1 as a parent.
#
# Order of processing:
#
# 0 - 3 (main), 3 (orphan), 4 (main), 4 (orphan), 5 (orphan), 2 (orphan, then 5 becomes main)
#
#
$:.unshift( File.expand_path("../../lib", __FILE__) )

require 'bitcoin'
require_relative '../../support/blockchain'

blockchain = Blockchain.new
blockchain.set_network_rules(1) # maturity

# genesis (block 0)

height = blockchain.next_height(:main)
time = blockchain.time
b = blockchain.build_next_block(nil, height, [], time)
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

# main block 1
height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

# record block 1 as the fork point
fork_block = b
fork_height = height

# main block 2
height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

# orphan block 2 -- this is the missing parent which will show up in the end
orphan_parent = blockchain.build_next_block(fork_block, fork_height+1, [], time)

# main block 3
height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

# orphan block 3
orphan_b = blockchain.build_next_block(orphan_parent, fork_height+2, [], time)
blockchain.chain[:orphan][fork_height+2] = orphan_b
blockchain.add_block_in_sequence(orphan_b)

# for main block 4 redeem the output from block 1 and send to two new addresses

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

# main block 4
height = blockchain.next_height(:main)
b = blockchain.build_next_block(b, height, [new_tx], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:main][height] = b
blockchain.add_block_in_sequence(b)

# orphan block 4
orphan_b = blockchain.build_next_block(orphan_b, fork_height+3, [], time)
blockchain.chain[:orphan][fork_height+3] = orphan_b
blockchain.add_block_in_sequence(orphan_b)

# orphan block 5 -- include the exact same tx from main block 4
orphan_b = blockchain.build_next_block(orphan_b, fork_height+4, [new_tx], time+=Bitcoin.network[:next_block_time_target])
blockchain.chain[:orphan][fork_height+4] = orphan_b
blockchain.add_block_in_sequence(orphan_b)

# ... and the missing parent finally shows up
blockchain.chain[:orphan][fork_height+1] = orphan_parent
blockchain.add_block_in_sequence(orphan_parent)

puts blockchain.pretty_print_json
