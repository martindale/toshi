# Toshi: Bitcoin Node

トシ - Bright, intelligent

[![Build Status](https://magnum.travis-ci.com/coinbase/toshi.svg?token=q4SuyNeyMuRZNwTyVWkw&branch=master)](https://magnum.travis-ci.com/coinbase/toshi)

## Prerequisites

Vagrant will install and run all prerequisites (postgresql, redis):

1. Install [Vagrant](http://www.vagrantup.com/)
2. Run `vagrant up` to install and run dependencies

Handy Vagrant Commands:

* Run `vagrant halt` to cleanly shut down your VM
* Run `vagrant reload --provision` to rebuild VM (won't lose existing data)
* Run `vagrant destroy` to completely remove VM

## Run using docker

* Make sure docker is installed
* Run `docker build -t=coinbase/node .` from the repo root
* Run `docker run -e REDIS_URL=redis://... -e DATABASE_URL=postgres://... -e TOSHI_ENV=production coinbase/node foreman start` to run all processes in the Procfile within a container

## Running Toshi

1. Run `gem install bundler` to install bundler
2. Run `bundle install` to install all necessary gems
3. Run `foreman run rake db:migrate` to update database schema
4. Run `foreman start` to start the magic

## Running Tests Locally

1. Create the test database with `bundle exec rake db:create
   TOSHI_ENV=test`
2. Run `bundle exec rspec`

## Configuration

Toshi parses config/toshi.yml according to its current environment (determined
by the `TOSHI_ENV` environment variable). Toshi will default to the
`development` environment when run normally and the `test` environment during
rspec tests.

## HTTP API Draft

API consists of two parts:

1. Blockchain queries
2. Composing transactions (except for signing)

----------------------------------------------------

1.  Blockchain queries:

    * `.bin`: raw binary
    * `.hex`: raw binary, in hex form
    * `.json`: parsed in JSON dictionary (default if extension not specified)

    For GET requests, extension specifies the format of the returned data.
    For POST/PUT requests, extension specifies the format of the request body.

    1.  Blocks

			GET /api/blocks(.json)

        Block by hash or height:

            GET /api/blocks/<hash>(.json)
            GET /api/blocks/<height>(.json)
            GET /api/blocks/latest(.json)

       	Block transactions:

			GET /api/blocks/<hash>/transactions(.json)

    2.  Transactions

        Transaction by hash:

            GET /api/transactions/<hash>(.json, .hex, .bin)

        Unconfirmed transaction pool:

            GET /api/unconfirmed_transactions(.json)

    3.  Broadcasting transactions

        Post a transaction in HTTP body in a proper format. We only allow hex or binary to avoid any ambiguity

            POST /api/transactions(.hex)

	4.  Addresses

		Address balance details:

			GET /api/addresses/<hash>(.json)

		Address transactions:

			GET /api/addresses/<hash>/transactions(.json)

		Address unspent outputs:

			GET /api/addresses/<hash>/unspent_outputs(.json)
