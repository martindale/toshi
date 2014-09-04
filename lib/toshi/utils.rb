module Toshi

  module NodeTime
    # TODO add real adjusted_time clac
    def self.adjusted_time; Time.now.to_i; end
  end

  module Utils
    extend self

    def read_bootstrap_file(file, offset=0, height=-1, start_height=0, stop_height=nil, &blk)
      return false unless blk
      File.open(file, 'rb'){|file|
        loop{
          file.seek(offset)
          buf = file.read(8)
          break if buf == nil
          magic_head, size = buf.unpack("a4I")

          if Bitcoin.network[:magic_head] == magic_head

            height+=1
            break if height > stop_height if stop_height

            magic_size = 8
            file.seek(offset + magic_size)

            if height >= start_height
              data_orig = file.read(size)
              block = Bitcoin::Protocol::Block.new(data_orig)

              raise "No block at offset #{offset + magic_size}!" if !block

              if block.verify_mrkl_root == false
                p [:faild_verify_mrkl_root, block.hash, block.prev_block_hex, offset, size, height]; break
              end

              break unless blk.call(block, height, offset)
            end

            offset += (magic_size + size)
          else
            p [:magic_head_broken, Bitcoin.network[:magic_head], magic_head]
            break
          end
        }
      }
    end

    def bin_to_hex_hash(hash)
      return nil if !hash
      hash.reverse.unpack('H*').first
    end

    def hex_to_bin_hash(hash)
      return nil if !hash
      [hash].pack('H*').reverse
    end
  end

  def self.db_stats
    s = Sidekiq::Stats.new
    {
      blocks: Toshi::Models::Block.count, transactions: Toshi::Models::Transaction.count, inputs: Toshi::Models::Input.count, outputs: Toshi::Models::Output.count,
      sidekiq: { queues: s.queues, processed: s.processed, failed: s.failed }
    }
  end
end

class Bitcoin::P::Block; attr_accessor :additional_fields; end
class Bitcoin::P::Tx; attr_accessor :additional_fields; end

class Numeric; def btc; "%.8f" % (self / 100000000.0); end; end
class Numeric; def btc_short; ("%.8f" % (self / 100000000.0)).gsub(/\.(\d+?)(0+)$/, ".\\1"); end; end
