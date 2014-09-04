# helpers for unconfirmed tx processing

def hex_to_bin(s)
  s.scan(/../).map { |x| x.hex }.pack('c*')
end

def build_nonstandard_tx(blockchain, prev_txs, prev_tx_output_indexes, ver=Toshi::CURRENT_TX_VERSION, lock_time=nil, output_pk_script=nil, output_key=nil)
  new_tx = Bitcoin::Protocol::Tx.new
  new_tx.ver = ver
  is_p2sh_input = false

  prev_txs.each_with_index{|prev_tx, i|
    new_tx.add_in Bitcoin::Protocol::TxIn.new(prev_tx.binary_hash, prev_tx_output_indexes[i], 0)
    if lock_time
      new_tx.lock_time = lock_time
      new_tx.in[0].instance_variable_set(:@sequence, "\x00\x00\x00\x01")
    end

    value = prev_tx.outputs[prev_tx_output_indexes[i]].value

    if !output_pk_script
      key = output_key ? output_key : blockchain.new_key
      txout = Bitcoin::Protocol::TxOut.value_to_address(value, key.addr)
    else
      txout = Bitcoin::Protocol::TxOut.new(value, output_pk_script)
    end

    new_tx.add_out txout
  }

  prev_txs.each_with_index{|prev_tx, i|
    prev_pk_script = Bitcoin::Script.new(prev_tx.outputs[prev_tx_output_indexes[i]].script)
    is_p2sh = prev_pk_script.is_p2sh?

    if is_p2sh
      address = prev_pk_script.get_p2sh_address
      inner_script = blockchain.p2sh[address]['inner_script']
      prev_pk_script = Bitcoin::Script.new(hex_to_bin(inner_script))
      is_p2sh_input = true
    end

    if prev_pk_script.is_multisig?
      sigs = []
      hash = new_tx.signature_hash_for_input(i, prev_tx)

      prev_pk_script.get_multisig_addresses.each{|addr|
        privkey = blockchain.wallet[addr]['privkey']
        key = Bitcoin::Key.from_base58(privkey)
        sigs << key.sign(hash)+"\x01"
      }

      new_tx.in[i].script_sig = Bitcoin::Script.to_multisig_script_sig(*sigs)
    else
      privkey = blockchain.wallet[prev_pk_script.get_address]['privkey']
      key = Bitcoin::Key.from_base58(privkey)
      signature = key.sign(new_tx.signature_hash_for_input(i, prev_tx))

      if prev_tx.is_coinbase? || is_p2sh
        new_tx.in[i].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, nil)
      else
        pubkey = [key.pub].pack("H*")
        new_tx.in[i].script_sig = Bitcoin::Script.to_signature_pubkey_script(signature, pubkey)
      end
    end

    if is_p2sh
      # append serialized script to scriptSig
      new_tx.in[i].script_sig += Bitcoin::Script.from_string("#{prev_pk_script.to_payload.unpack('H*').first}").raw
    end
  }

  new_tx = Bitcoin::Protocol::Tx.new(new_tx.to_payload)

  prev_txs.each_with_index{|prev_tx, i|
    # TODO: why aren't p2sh signatures verifying?
    raise "failed to generate tx" unless new_tx.verify_input_signature(i, prev_tx) == true || is_p2sh_input
  }

  new_tx
end


