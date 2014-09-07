# Toshi

[![Build Status](https://magnum.travis-ci.com/coinbase/toshi.svg?token=q4SuyNeyMuRZNwTyVWkw&branch=master)](https://magnum.travis-ci.com/coinbase/toshi)

Toshi is a complete implementation of the bitcoin protocol, written in Ruby and backed by PostgreSQL. It provides a RESTful API that is ideal for building scalable web applications or analyzing blockchain data.

Toshi is designed to be 100% compatible with [Bitcoin Core](https://github.com/bitcoin/bitcoin). It performs complete transaction and block verification, and is tested against TheBlueMatt's [regression test suite](https://github.com/TheBlueMatt/test-scripts).

Toshi was built at [Coinbase](https://coinbase.com) to meet our requirements for a highly scalable bitcoin node. It is currently used for querying blockchain data, but our goal is for Toshi to replace our core bitcoin infrastructure in the near future.

## Features

 * Complete Bitcoin node implementation
 * Does not require bitcoind
 * Fully tested against TheBlueMatt's [regression test suite](https://github.com/TheBlueMatt/test-scripts)
 * PostgeSQL backed (more convenient for web applications and research)
 * JSON, Hex, and Binary API
 * Simple web interface to monitor node status

## Comparison to bitcoind

Toshi is written in Ruby and uses a PostgreSQL datastore. Bitcoind is written in C++ and uses LevelDB.  Bitcoind is much faster at syncing with the blockchain, but provides a limited interface to blockchain data through LevelDB.  Toshi is slower to sync but allows much more complex queries against the blockchain in SQL. This makes it easier to create web applications or to do blockchain analysis.

## Usage

#### Using the hosted version

Coinbase maintains a hosted version of Toshi that you can use at:

**[http://bitcoin.network.coinbase.com](http://bitcoin.network.coinbase.com)**

This is the easiest way to get up and running. You can also run your own version of Toshi as described below.

#### Running your own copy in production

Toshi can be installed on Heroku in just a few minutes:

    $ git clone https://github.com/coinbase/toshi.git
    $ cd toshi
    $ heroku create [APP NAME]
    $ heroku addons:add heroku-postgresql:dev
    $ heroku addons:add redistogo
    $ git push heroku master
    $ heroku run rake db:migrate
    $ heroku scale block_worker=1 peer_manager=1 transaction_worker=2 web=1
    $ heroku open
    $ heroku logs -t

#### Running your own copy in development

Toshi uses [Vagrant](http://www.vagrantup.com/) to install and run all prerequisites (postgresql, redis).

    $ git clone https://github.com/coinbase/toshi.git
    $ cd toshi
    $ vagrant up # other useful commands: 'vagrant halt', 'vagrant reload --provision', 'vagrant destroy'
    $ gem install bundler
    $ bundle install
    $ foreman run rake db:migrate
    $ foreman start
    $ open http://localhost:5000/

Alternatively, you can use Docker:

    $ docker build -t=coinbase/node .
    $ docker run -e REDIS_URL=redis://... -e DATABASE_URL=postgres://... -e TOSHI_ENV=production coinbase/node foreman start


## HTTP API

> Note: The Toshi API provides raw blockchain data only. If you are looking for APIs to store bitcoin securely, buy/sell bitcoin, send/request bitcoin, accept merchant payments, etc) please check out the [Coinbase API](https://coinbase.com/docs/api/overview).

The API supports three data types by adding an extension on any URL.

`.json` - JSON (default if none specified)
`.hex` - raw binary, in hex form
`.bin` - raw binary

For GET requests, the extension specifies the format of the returned data.
For POST/PUT requests, the extension specifies the format of the request body.

**TODO is this correct?** Any API call which returns as list can also be passed an `offset` or `limit` parameter.  The default `limit` is 50.


    # Blocks
    GET /api/blocks                             # Get a paginated list of blocks
    GET /api/blocks/<hash>                      # Get a block by hash
    GET /api/blocks/<height>                    # Get a block by height
    GET /api/blocks/latest                      # Get the latest block
    GET /api/blocks/<hash>/transactions         # Get transactions in a block

    # Transactions
    GET /api/transactions/<hash>                # Get transaction by hash
    GET /api/unconfirmed_transactions           # Get list of unconfirmed transactions
    POST /api/transactions                      # Broadcast a transaction to the network

    # Addresses
    GET /api/addresses/<hash>                   # Get address balance and details
    GET /api/addresses/<hash>/transactions      # Get address transactions
    GET /api/addresses/<hash>/unspent_outputs   # Get unspent outputs on an address


## Configuration

Toshi parses `config/toshi.yml` according to its current environment (determined by the `TOSHI_ENV` environment variable). Toshi will default to the `development` environment if one isn't specified and the `test` environment during rspec tests.

Toshi will use the `config/toshi.yml.example` file if the `config/toshi.yml` file does not exist.

## Testing

You can run the test suite for Toshi as follows:

    $ rake db:create TOSHI_ENV=test
    $ rspec

## Contributing

1. Fork this repo and make changes in your own fork
2. Run existing tests with `bundle exec rspec` and add a new test for your changes if applicable.
3. Commit your changes and push to your fork `git push origin master`
4. Create a new pull request and submit it back to us!
