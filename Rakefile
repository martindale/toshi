require_relative 'config/application'

task :bundle do
  sh 'bundle install --path  .bundle'
end

namespace :db do
  desc "Run database migrations"
  task :migrate, [:version] do |t, args|
    Sequel.extension :migration
    db = Sequel.connect(Toshi.settings[:database])
    if args[:version]
      puts "Migrating to version #{args[:version].to_i}"
      Sequel::Migrator.run(db, "db/migrations", target: args[:version].to_i)
    else
      puts "Migrating to latest"
      Sequel::Migrator.run(db, "db/migrations")
    end
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

task :force_test_env do
  ENV['TOSHI_ENV'] = 'test'
end

task :default => %w(force_test_env db:migrate test)

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
