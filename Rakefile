require_relative 'config/application'

task :bundle do
  sh 'bundle install --path  .bundle'
end

namespace :db do
  desc "Run database migrations"
  task :migrate, [:version] do |t, args|
    Sequel.extension :migration
    puts "sequel connect to #{Toshi.settings[:database_url]}"
    db = Sequel.connect(Toshi.settings[:database_url])
    if args[:version]
      puts "Migrating to version #{args[:version]}"
      Sequel::Migrator.run(db, "db/migrations", target: args[:version].to_i)
    else
      puts "Migrating to latest"
      Sequel::Migrator.run(db, "db/migrations")
    end
  end

  desc "Create test and dev databases"
  task :create do
    db_uri = URI(Toshi.settings[:database_url])
    db_port = db_uri.port
    db_host = db_uri.host
    db_user = db_uri.user
    db_name = db_uri.path[1..-1]
    ENV["PGPASSWORD"] = db_uri.password
    sys_db_args = "-p #{db_port} -h #{db_host} -U #{db_user}"
    system "dropdb #{sys_db_args} #{db_name}"
    system "createdb #{sys_db_args} #{db_name}"
    system "bundle exec sequel -E -m db/migrations #{Toshi.settings[:database_url]}"
    Rake::Task['db:migrate'].invoke
  end
end

task :sidekiq do
  FileUtils.mkdir_p(ENV['COINBASE_LOG_PATH'] || 'run')

  log_path = ENV['COINBASE_LOG_PATH'] ? File.join(ENV['COINBASE_LOG_PATH'], 'sidekiq.log') : 'log/sidekiq.log'
  threads = ENV['COINBASE_SIDEKIQ_THREADS'] || "20"
  sh "bundle exec sidekiq -L #{log_path} -c #{threads} -r ./config/environment.rb"
end

task :api do
  exec 'bundle exec ruby ./bin/api.rb'
end

task :web_sock do
  exec 'bundle exec thin -C thin.conf restart'
end

task :console do
  exec 'bundle exec ruby -rirb -rirb/completion -e "include Toshi; IRB.start" -r./config/environment.rb '
end

task :test do
  exec 'bundle exec rspec spec'
end

task :default => ['db:create', 'db:migrate', 'test']

# Time the bootstrapping of the first 40K blocks of testnet3
task :perf do
  bootstrap_file = 'testnet3_bootstrap_103000.dat'
  if !File.file?(bootstrap_file)
    puts "Downloading bootstrap file"
    system "curl -o #{bootstrap_file} http://l.uphnix.de/#{bootstrap_file}"
  end
  puts "Logging results to log/bootstrap-perf.log"
  system "time BOOTSTRAP_FILE=#{bootstrap_file} bin/bootstrap.rb 40000 > log/bootstrap-perf.log"
end

# fix ledger entries with missing previous output info
task :fixit do
  Toshi.db = Sequel.connect(Toshi.settings[:database_url])
  output_cache = Toshi::OutputsCache.new
  storage = Toshi::BlockchainStorage.new(output_cache)

  storage.transaction do
    start_time = Time.now
    puts "#{start_time.to_i}| Looking for affected ledger entries"

    # this is going to be really slow. there's no indexed way to find these entries.
    # we're looking for input entries with 0 amounts.
    affected_tx_ids = Toshi.db[:address_ledger_entries].exclude(input_id: nil).where(amount: 0).select_map(:transaction_id)

    end_time = Time.now
    puts "#{end_time.to_i}| Found #{affected_tx_ids.size} entries in #{end_time.to_i - start_time.to_i} seconds"
    start_time = end_time
    lookup_ids = affected_tx_ids.uniq
    puts "#{start_time.to_i}| Looking up #{lookup_ids.size} affected transaction models"

    counter = 0
    bitcoin_txs, tx_ids_by_hsh = [], {}
    Toshi::Models::Transaction.where(id: lookup_ids).each{|t|
      puts "#{Time.now.to_i}| Model lookup complete" if counter == 0
      counter += 1
      if t.is_coinbase?
        # handle coinbases specially
        block = t.block
        t.update_address_ledger_for_coinbase(t.total_out_value - block.fees) if block
      else
        tx_ids_by_hsh[t.hsh] = t.id
      end
      if counter % 10000 == 0
        puts "#{Time.now.to_i}| Processed #{counter} txs of #{lookup_ids.size}"
      end
    }

    end_time = Time.now
    puts "#{end_time.to_i}| Processed txs in #{end_time.to_i - start_time.to_i} seconds"
    start_time = end_time
    puts "#{start_time.to_i}| Fetching raw txs"

    counter = 0
    Toshi::Models::RawTransaction.where(hsh: tx_ids_by_hsh.keys.uniq).each{|raw|
      bitcoin_txs << raw.bitcoin_tx
      counter += 1
      if counter % 10000 == 0
        puts "#{Time.now.to_i}| Fecthed #{counter} raw txs"
      end
    }

    end_time = Time.now
    puts "#{end_time.to_i}| Loaded raw txs in #{end_time.to_i - start_time.to_i} seconds"
    start_time = end_time
    puts "#{start_time.to_i}| Loading output cache"

    storage.load_output_cache(bitcoin_txs)

    end_time = Time.now
    puts "#{end_time.to_i}| Loaded output cache in #{end_time.to_i - start_time.to_i} seconds"
    start_time = end_time
    puts "#{start_time.to_i}| Fixing entries"

    Toshi::Models::Transaction.update_address_ledger_for_missing_inputs(tx_ids_by_hsh, output_cache)

    end_time = Time.now
    puts "#{end_time.to_i}| Fixed entries in #{end_time.to_i - start_time.to_i} seconds"
  end
end
