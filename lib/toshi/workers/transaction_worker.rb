require "sidekiq"
require "sidekiq-unique-jobs"

module Toshi
  module Workers
    class TransactionWorker
      include Sidekiq::Worker

      sidekiq_options unique: true, unique_job_expiration: (5*60), unique_args: ->(args) { [ args.first ] },
                       queue: :transactions, :retry => true

      def perform(tx_hash, _sender)
        return if Toshi::Models::Transaction.where(hsh: tx_hash).first
        return if Toshi::Models::UnconfirmedTransaction.where(hsh: tx_hash).first
        tx = Toshi::Models::UnconfirmedRawTransaction.where(hsh: tx_hash).first
        return unless tx

        begin
          result = processor.process_transaction(tx.bitcoin_tx, raise_error=true)
        rescue Toshi::Processor::ValidationError => ex
          # we want anything else to blow up
          logger.warn{ ex.message }
        end

        logger.info{ result }

        # announce a new memory pool tx to clients
        tx = Toshi::Models::UnconfirmedTransaction.where(hsh: tx_hash).first if result
        if result && tx.in_memory_pool?
          processor.mq.clients_push_all({ 'msg' => 'new_tx', 'hash' => tx_hash })
        end
      end

      def processor
        @@processor ||= Toshi::Processor.new
      end
    end
  end
end
