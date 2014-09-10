# Toshi

[![Build Status](https://magnum.travis-ci.com/coinbase/toshi.svg?token=q4SuyNeyMuRZNwTyVWkw&branch=master)](https://magnum.travis-ci.com/coinbase/toshi)

Toshi is a complete implementation of the Bitcoin protocol, written in Ruby and backed by PostgreSQL. It provides a RESTful API that is ideal for building scalable web applications or analyzing blockchain data.

Toshi is designed to be 100% compatible with [Bitcoin Core](https://github.com/bitcoin/bitcoin). It performs complete transaction and block verification, and passes 100% of TheBlueMatt's [regression test suite](https://github.com/TheBlueMatt/test-scripts).

Toshi was built at [Coinbase](https://coinbase.com) to meet our requirements for a highly scalable Bitcoin node. Our goal is for Toshi to replace our core Bitcoin network infrastructure in the near future.

## Features

 * Complete Bitcoin node implementation
 * Fully passes TheBlueMatt's [regression test suite](https://github.com/TheBlueMatt/test-scripts)
 * PostgeSQL backed (more convenient for web applications and research)
 * JSON, Hex, and Binary API
 * Simple web interface to monitor node status

## Comparison to Bitcoin Core

Toshi is a Bitcoin implementation designed for building scalable web applications. It allows you to query the blockchain using a REST API or raw SQL. It comprises a number of individual services, using a shared database. Because Toshi indexes every transaction and block in the blockchain, it requires much more space to store the blockchain than Bitcoin Core (~270GB vs ~25GB as of September 2014). However, this makes it possible to run much richer queries that would otherwise not be possible with Bitcoin Core.

Bitcoin Core (the reference implementation) is designed to run on a single server, and uses a mixture of raw files and LevelDB to store the blockchain. It allows you to query the blockchain using a JSON-RPC interface.

Some examples of queries which Toshi can easily answer, which are not possible with Bitcoin Core:

* List all unspent outputs for any address (Bitcoin Core only indexes unspent outputs for specific addresses added to the local "wallet").
* Get the balance of any address
* Get the balance of any address at a specific point in time
* Find all transactions for any address
* Find all transactions in a certain time period
* Find all transactions over a certain amount
* Find previous outputs (and addresses) for any given set of transactions

## Usage

### Hosted Toshi

Coinbase maintains a hosted version of Toshi that you can use at:

**[http://bitcoin.network.coinbase.com](http://bitcoin.network.coinbase.com)**

This is the easiest way to get up and running. You can also run your own version of Toshi as described below.

### Running Toshi locally

Toshi uses [Vagrant](http://www.vagrantup.com/) to install and run all prerequisites (postgresql, redis).

    $ git clone https://github.com/coinbase/toshi.git
    $ cd toshi
    $ vagrant up # other useful commands: 'vagrant halt', 'vagrant reload --provision', 'vagrant destroy'
    $ gem install bundler
    $ bundle install
    $ foreman run rake db:create
    $ foreman start
    $ open http://localhost:5000/

Alternatively, you can use Docker:

    $ docker build -t=coinbase/node .
    $ docker run -e REDIS_URL=redis://... -e DATABASE_URL=postgres://... -e TOSHI_ENV=production coinbase/node foreman start

### Deployment

Toshi can be deployed directly to Heroku:

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/coinbase/toshi)

Toshi can also be installed on your own server. You will need:

* PostgreSQL (300gb+ disk space required to sync mainnet)
* Redis (50mb+ RAM recommended)
* Ruby 2.0.0+

To run Toshi on your server, simply:

    $ git clone https://github.com/coinbase/toshi.git
    $ cd toshi
    $ cp config/toshi.yml.example config/toshi.yml
    $ vi config/toshi.yml
    $ REDIS_URL=redis://... DATABASE_URL=postgres://... TOSHI_ENV=production bundle exec foreman start

## API

> Note: The Toshi API provides raw blockchain data only. If you are looking for APIs to store bitcoin securely, buy/sell bitcoin, send/request bitcoin, accept merchant payments, etc) please check out the proprietary [Coinbase API](https://coinbase.com/docs/api/overview).

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
    GET /api/transactions/unconfirmed           # Get list of unconfirmed transactions
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
