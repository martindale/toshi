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

task :redis_local do
  db_path   = File.expand_path(File.join(Dir.pwd, 'tmp/db_redis_test'))
  FileUtils.mkdir_p(db_path) unless File.directory?(db_path)
  sh %[sh -c 'echo "port 21002\nbind 127.0.0.1\ndaemonize no\nlogfile stdout\ndir \"#{db_path}\"" | redis-server -' 2>&1]
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

task :double_check do
  Toshi.db = Sequel.connect(Toshi.settings[:database_url])
  Toshi::Models::Address.all.each{|a|
    raise "BUG: balances don't match" if a.balance != a.utxo_balance
  }
end

task :cache_totals do
  Toshi.db = Sequel.connect(Toshi.settings[:database_url])
  Toshi.db.transaction do
    puts "#{Time.now.to_i}| Updating received"
    query = "update addresses
                    set total_received = o.total
                    from (select sum(outputs.amount) as total,
                                 addresses_outputs.address_id as addr_id
                                 from addresses_outputs, outputs
                                 where addresses_outputs.output_id = outputs.id and
                                       outputs.branch = #{Toshi::Models::Block::MAIN_BRANCH}
                                 group by addresses_outputs.address_id) o
                    where addresses.id = o.addr_id"
    Toshi.db.run(query)
    puts "#{Time.now.to_i}| Updating sent"
    query = "update addresses
                    set total_sent = o.total
                    from (select sum(outputs.amount) as total,
                                 addresses_outputs.address_id as addr_id
                                 from addresses_outputs, outputs
                                 where addresses_outputs.output_id = outputs.id and
                                       outputs.spent = true and
                                       outputs.branch = #{Toshi::Models::Block::MAIN_BRANCH}
                                 group by addresses_outputs.address_id) o
                    where addresses.id = o.addr_id"
    Toshi.db.run(query)
  end
end
