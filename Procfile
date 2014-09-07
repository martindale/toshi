web: bundle exec puma
block_worker: bundle exec sidekiq -q blocks -c 1 -r ./config/environment.rb
transaction_worker: bundle exec sidekiq -q transactions -c 1 -r ./config/environment.rb
peer_manager: bundle exec ruby bin/peer_manager.rb
