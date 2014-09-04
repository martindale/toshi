require 'bitcoin'

#
# Blockchain
#
# This class is used to build and encapsulate a custom blockchain for use with tests.
#
class Blockchain
  attr_accessor :time
  attr_accessor :chain
  attr_accessor :wallet
  attr_accessor :blocks
  attr_accessor :p2sh

  def initialize
    @chain = { main: {}, side: {}, orphan: {} }
    @wallet = {}
    @blocks = [] # in order to be processed
    @p2sh = {}
    @time = Time.now.to_i - (3600*2) # 2 hours ago
    set_network_rules
  end

  def set_network_rules(maturity=5, network=:testnet3)
    Bitcoin.network = network
    Bitcoin.network[:checkpoints] = {}
    Bitcoin.network[:proof_of_work_limit] = Bitcoin.encode_compact_bits("00ffff0000000000000000000000000000000000000000000000000000000000")
    Bitcoin.network[:coinbase_maturity] = maturity
    Bitcoin.network[:retarget_interval] = 126   # 2016
    Bitcoin.network[:retarget_time] = 3600      # 1209600
    Bitcoin.network[:next_block_time_target] = Bitcoin.network[:retarget_time] / Bitcoin.network[:retarget_interval] # 28 seconds
  end

  def current_height(branch=:main)
    @chain[branch].size-1
  end

  def next_height(branch=:main)
    current_height(branch) + 1
  end

  def gen_bip34_height(height)
    buf = [height].pack("V").gsub(/\x00+$/,"")
    [buf.bytesize, buf].pack("Ca*")
  end

  def build_coinbase_tx(height, fees=0, key=nil)
    tx = Bitcoin::P::Tx.new

    input = Bitcoin::P::TxIn.new(Bitcoin::P::TxIn::NULL_HASH, Bitcoin::P::TxIn::COINBASE_INDEX, 0, "", Bitcoin::P::TxIn::DEFAULT_SEQUENCE)
    input.script = gen_bip34_height(height) + 'built by Coinbase for regression testing'
    tx.inputs << input

    key = new_key if !key
    output = Bitcoin::P::TxOut.new(Bitcoin.block_creation_reward(height) + fees, Bitcoin::Script.from_string("#{key.pub} OP_CHECKSIG").to_payload)
    tx.outputs << output

    Bitcoin::P::Tx.new(tx.to_payload)
  end

  def build_next_block(prev_block, next_height, txs=[], time=Time.now.to_i, fees=0, key=nil)
    b = Bitcoin::P::Block.new(nil)
    b.prev_block = prev_block ? prev_block.hash.htb.reverse : "\x00"*32
    b.bits = prev_block ? prev_block.bits : Bitcoin.network[:proof_of_work_limit]
    b.ver, b.nonce, b.time = 2, 0, time
    b.tx = [ build_coinbase_tx(next_height, fees, key), *txs ]
    b.mrkl_root = Bitcoin.hash_mrkl_tree(b.tx.map(&:hash)).last.htb.reverse

    # mine
    target = Bitcoin.decode_compact_bits(b.bits).to_i(16)
    b.recalc_block_hash
    until b.hash.to_i(16) < target
      b.nonce += 1
      (b.time += 1; b.nonce = 0) if b.nonce > 0xffffffff
      b.recalc_block_hash
    end

    raise "Payload Error" unless Bitcoin::P::Block.new(b.to_payload).to_payload == b.to_payload
    b
  end

  def add_block_in_sequence(block)
    @blocks << block
    if @blocks.length == 1
      Bitcoin.network[:genesis_hash] = block.hash
    end
  end

  def new_key(label='')
    key = Bitcoin::Key.generate
    @wallet[key.addr] = { 'privkey' => key.to_base58, 'label' => label }
    key
  end

  def new_p2sh(m, *keys)
    if keys.length == 1
      inner_script = Bitcoin::Script.to_pubkey_script(keys.first.pub)
    else
      pubkeys = keys.map{|k| k.pub}
      inner_script = Bitcoin::Script.to_multisig_script(m, *pubkeys)
    end

    hash160 = Bitcoin.hash160(inner_script.unpack('H*').first)
    address = Bitcoin.hash160_to_p2sh_address(hash160)
    p2sh_script = Bitcoin::Script.to_p2sh_script(hash160)

    @p2sh[address] = { 'inner_script' => inner_script.unpack('H*').first,
                       'p2sh_script' => p2sh_script.unpack('H*').first }
    p2sh_script
  end

  def address_from_label(label)
    @wallet.select{|k,v| v['label'] == label }.keys.first
  end

  def pretty_print_json
    puts JSON.pretty_generate({ protocol_rules: Bitcoin.network, chain: @chain, wallet: @wallet, blocks: @blocks })
  end

  def load_from_json(filename)
    json = JSON.parse(fixtures_file(filename))
    protocol_rules, @chain, @wallet = json.values_at('protocol_rules', 'chain', 'wallet')
    if @blocks = json['blocks']
      @blocks.each_with_index{|block, idx|
        @blocks[idx] = Bitcoin::P::Block.from_hash(block)
      }
    end

    # If the fixture contains protocol rules, apply them.
    # Otherwise, use default rules.
    (protocol_rules || Bitcoin::NETWORKS[Bitcoin.network_name]).each do |k,v|
      Bitcoin.network[k.to_sym] = v
    end

    ['main', 'side','orphan'].each{|branch|
      @chain[branch].each{|k,v|
        if v.is_a?(Array)
          @chain[branch][k] = v.map{|e| Bitcoin::P::Block.from_hash(e) }
        else
          @chain[branch][k] = Bitcoin::P::Block.from_hash(v)
        end
      }
    }

    Bitcoin.network[:genesis_hash] = @chain['main']['0'].hash
  end
end
