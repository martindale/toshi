---
title: API Reference

language_tabs:
  - shell

toc_footers:
  - <a href='https://github.com/tripit/slate'>Documentation Powered by Slate</a>

search: true
---

# Introduction

Welcome to the Toshi API! You can use our API to access Toshi API endpoints, which can get information on various blocks, transactions, and addresses in Toshi database.

# Blocks

## Get latest blocks

```shell
curl "https://network.coinbase.com/api/v0/blocks"
```

> The above command returns JSON structured like this:

```json
[
  {
    "hash": "00000000000000001df71c4b32cf57134799dc3b770695dd4ed88fd0dfb70127",
    "branch": "orphan",
    "previous_block_hash": "00000000000000001e8eb43069089fc7efce72d5813238318f9edd80a19540a4",
    "next_blocks": [],
    "height": 21,
    "confirmations": 0,
    "merkle_root": "f50c3bd37b752625eab2640f1ec75924e0c1ec145b62dded418f937da2dd7900",
    "time": "2014-09-09T20:38:46Z",
    "created_at": "2014-09-09T20:45:06Z",
    "nonce": 1806449737,
    "bits": 405280238,
    "difficulty": 27428630902.257942,
    "reward": 5000000000,
    "fees": 0,
    "total_out": 0,
    "size": 749160,
    "transactions_count": 458,
    "version": 2,
    "transaction_hashes": [
      "e56cb342a7ce13f6812d94975585222ba63198bf6139df44ed54169fea58b3aa",
      "..."
    ]
  },
  {
    "hash": "00000000000000001e8eb43069089fc7efce72d5813238318f9edd80a19540a4",
    "branch": "orphan",
    "previous_block_hash": "000000000000000016ec85d0ec5c10f7d738ca7333ee917d4dcb13776a93219d",
    "next_blocks": [
      {
        "hash": "00000000000000001df71c4b32cf57134799dc3b770695dd4ed88fd0dfb70127",
        "branch": "orphan",
        "height": 21
      }
    ],
    "height": 20,
    "confirmations": 0,
    "merkle_root": "2529eba2de6849e97efb644754141943c10ed4ded6f24096554bf79c4320cc2b",
    "time": "2014-09-09T20:31:35Z",
    "created_at": "2014-09-09T20:44:57Z",
    "nonce": 727759134,
    "bits": 405280238,
    "difficulty": 27428630902.257942,
    "reward": 5000000000,
    "fees": 0,
    "total_out": 0,
    "size": 749132,
    "transactions_count": 632,
    "version": 2,
    "transaction_hashes": [
      "a5971829e9dab94ba723eacb424bbcb12a896e0a3e9cdc563d6b132ee0f8740c",
      "..."
    ]
  }
]
```

This endpoint retrieves list of latest blocks.

### HTTP Request

`GET https://network.coinbase.com/api/<version>/blocks`

## Get latest block

```shell
curl "https://network.coinbase.com/api/v0/blocks/latest"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "0000000000000000085a5e54dddaaf822e06011b38201082b74bea51ec08727c",
  "branch": "main",
  "previous_block_hash": "00000000000000002323c992d7d4d6e742270bc6a71d94bbb2b28ff623a79de1",
  "next_blocks": [
    {
      "hash": "000000000000000015c7ca7f4f29ecaae86fc40a7b9dc385fefc38c3b733a863",
      "branch": "orphan",
      "height": 270
    }
  ],
  "height": 319420,
  "confirmations": 0,
  "merkle_root": "3e8a8e4f727fce772ac8bba486f603145d7ed238cb50088e68aa814d210bfb11",
  "time": "2014-09-06T18:08:38Z",
  "created_at": "2014-09-06T18:13:12Z",
  "nonce": 1605584395,
  "bits": 405280238,
  "difficulty": 27428630902.257942,
  "reward": 2500000000,
  "fees": 12323529,
  "total_out": 207279237910,
  "size": 429018,
  "transactions_count": 820,
  "version": 2,
  "transaction_hashes": [
    "72e6f86887d3612e7e88e3b092f5724974076174176d914be1f72ed707e20000",
    "..."
  ]
}
```

This endpoint retrieves latest block.

### HTTP Request

`GET https://network.coinbase.com/api/<version>/blocks/latest`

## Get block by hash or height

```shell
curl "https://network.coinbase.com/api/v0/blocks/00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
  "branch": "main",
  "previous_block_hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
  "next_blocks": [
    {
      "hash": "000000006a625f06636b8bb6ac7b960a8d03705d1ace08b1a19da3fdcc99ddbd",
      "branch": "main",
      "height": 2
    }
  ],
  "height": 1,
  "confirmations": 320849,
  "merkle_root": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
  "time": "2009-01-09T02:54:25Z",
  "created_at": "2014-09-05T01:01:26Z",
  "nonce": 2573394689,
  "bits": 486604799,
  "difficulty": 1,
  "reward": 5000000000,
  "fees": 0,
  "total_out": 5000000000,
  "size": 215,
  "transactions_count": 1,
  "version": 1,
  "transaction_hashes": [
    "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098"
  ]
}
```

This endpoint retrieves block by hash or height.

### HTTP Request

`GET https://network.coinbase.com/api/<version>/blocks/<hash or height>`

## Get block transactions

```shell
curl "https://network.coinbase.com/api/v0/blocks/00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048/transactions"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
  "branch": "main",
  "previous_block_hash": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f",
  "next_blocks": [
    {
      "hash": "000000006a625f06636b8bb6ac7b960a8d03705d1ace08b1a19da3fdcc99ddbd",
      "branch": "main",
      "height": 2
    }
  ],
  "height": 1,
  "confirmations": 320849,
  "merkle_root": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
  "time": "2009-01-09T02:54:25Z",
  "created_at": "2014-09-05T01:01:26Z",
  "nonce": 2573394689,
  "bits": 486604799,
  "difficulty": 1,
  "reward": 5000000000,
  "fees": 0,
  "total_out": 5000000000,
  "size": 215,
  "transactions_count": 1,
  "version": 1,
  "transactions": [
    {
      "hash": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
      "version": 1,
      "lock_time": 0,
      "size": 134,
      "inputs": [
        {
          "previous_transaction_hash": "0000000000000000000000000000000000000000000000000000000000000000",
          "output_index": 4294967295,
          "amount": 5000000000,
          "coinbase": "04ffff001d0104"
        }
      ],
      "outputs": [
        {
          "amount": 5000000000,
          "spent": false,
          "script": "0496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858ee OP_CHECKSIG",
          "script_hex": "410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858eeac",
          "script_type": "pubkey",
          "addresses": [
            "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
          ]
        }
      ],
      "amount": 5000000000,
      "fees": 0,
      "confirmations": 320849,
      "block_height": 1,
      "block_hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
      "block_time": "2009-01-09T02:54:25Z",
      "block_branch": "main"
    }
  ]
}
```

This endpoint retrieves latest block and full transactions list.

### HTTP Request

`GET https://network.coinbase.com/api/<version>/blocks/<hash or height>/transactions`

# Transactions

## Get transaction

```shell
curl "https://network.coinbase.com/api/v0/transactions/0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098",
  "version": 1,
  "lock_time": 0,
  "size": 134,
  "inputs": [
    {
      "previous_transaction_hash": "0000000000000000000000000000000000000000000000000000000000000000",
      "output_index": 4294967295,
      "amount": 5000000000,
      "coinbase": "04ffff001d0104"
    }
  ],
  "outputs": [
    {
      "amount": 5000000000,
      "spent": false,
      "script": "0496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858ee OP_CHECKSIG",
      "script_hex": "410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858eeac",
      "script_type": "pubkey",
      "addresses": [
        "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
      ]
    }
  ],
  "amount": 5000000000,
  "fees": 0,
  "confirmations": 320849,
  "block_height": 1,
  "block_hash": "00000000839a8e6886ab5951d76f411475428afc90947ee320161bbf18eb6048",
  "block_time": "2009-01-09T02:54:25Z",
  "block_branch": "main"
}
```

This endpoint retrieves transaction information.

### HTTP Request

`GET https://network.coinbase.com/api/<version>/transactions/<hash>`

## Relay transaction

```shell
curl https://network.coinbase.com/api/v0/transactions \
    -d '{"hex": "0100000001ea..."}' \
    -X PUT
```

> The above command returns JSON structured like this:

```json
{
  "hash": "2eaa7..."
}
```

This endpoint accepts a signed transaction in hex format and sends it to the network

### HTTP Request

`GET https://network.coinbase.com/api/<version>/transactions/<hash>`

### Arguments

Parameter | Type    | Description
--------- | ------- | -----------
hex | string | A hex representation of the signed transaction.

### Return value

Parameter | Type    | Description
--------- | ------- | -----------
hash | string | The newly created transaction hash.

## Unconfirmed transactions

```shell
curl "https://network.coinbase.com/api/v0/transactions/unconfirmed"
```

> The above command returns JSON structured like this:

```json
[
  {
    "hash": "2555e6ce792de8060e0128f613898a089ef76d4772e995cfec559b5cb09fe0e1",
    "version": 1,
    "lock_time": 0,
    "size": 403,
    "inputs": [
      {
        "previous_transaction_hash": "38c1e2ed3bc97505f7087d4e4c3c8573ba6a3c0dd213a697d77362e9a00eb0d4",
        "output_index": 4,
        "amount": 6150,
        "script": "3044022061419e5a780cf3df182c8a22345bc607385e7566c1dd1b27a4482cb9e540c51902200f87da133fa7dc298df4d1da382be914362206600b012083837fb6e99bbdec0901 042ce9a47c8ef78395e64e454d72898c522443adddbd4fe7adfd6d7b6a19f2603cb555f54e70a78b32a07c6ee2c1624dc85a2b397b3bfe8d4651baf0e7745dae84",
        "addresses": [
          "1D7A41TZFdEfkgvX3rJRWaodRyby7aeoMx"
        ]
      },
      {
        "previous_transaction_hash": "91f6428581eb2ee287415238c64d043d21db2ab9918cf81f9d62413a57ab8dbf",
        "output_index": 27,
        "amount": 5620,
        "script": "3045022100a9bdd2d33e9d7f3e33559855f8127f0ff4282457d88263a7e832636eb6963d4902201acde649f156967c3c52cf86383ab956d5418c143adf3e268e27019e55dcdf9e01 042ce9a47c8ef78395e64e454d72898c522443adddbd4fe7adfd6d7b6a19f2603cb555f54e70a78b32a07c6ee2c1624dc85a2b397b3bfe8d4651baf0e7745dae84",
        "addresses": [
          "1D7A41TZFdEfkgvX3rJRWaodRyby7aeoMx"
        ]
      }
    ],
    "outputs": [
    {
      "amount": 11770,
      "spent": false,
      "script": "OP_DUP OP_HASH160 2aa131bc2ef23c552edba80f8af020b996afbd5e OP_EQUALVERIFY OP_CHECKSIG",
      "script_hex": "76a9142aa131bc2ef23c552edba80f8af020b996afbd5e88ac",
      "script_type": "hash160",
      "addresses": [
        "14tQV2qSYKn8yFmsU9tuRkwK6RoMZqyDLA"
      ]
    }
    ],
    "amount": 11770,
    "fees": 0,
    "confirmations": 0,
    "pool": "memory"
  }
]
```

This endpoint returns a list of unconfirmed transactions

### HTTP Request

`GET https://network.coinbase.com/api/<version>/addresses/<hash>`

# Addresses

## Get address balance

```shell
curl "https://network.coinbase.com/api/v0/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX",
  "balance": 5002467686,
  "received": 5002477686,
  "sent": 0,
  "unconfirmed_received": 10000,
  "unconfirmed_sent": 0,
  "unconfirmed_balance": 5002477686
}
```

This endpoint returns address balance and details

### HTTP Request

`GET https://network.coinbase.com/api/<version>/addresses/<hash>`

## Get address transactions

```shell
curl "https://network.coinbase.com/api/v0/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX/transactions"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX",
  "balance": 5002467686,
  "received": 5002477686,
  "sent": 0,
  "unconfirmed_received": 10000,
  "unconfirmed_sent": 0,
  "unconfirmed_balance": 5002477686,
  "transactions": [
    {
      "hash": "24087a08309ea5796ef139e65f13ce10db1e4465057b665b9d5102a640aac6be",
      "version": 1,
      "lock_time": 0,
      "size": 257,
      "inputs": [{
        "previous_transaction_hash": "4aecda969d15b7a75db66b6a90a8cf95f801cc2f68c0699a2816ae41252d9294",
        "output_index": 1,
        "amount": 1011640,
        "script": "3044022017d58d70df1adabee104a8ba1d53d0b520cfed73b4a7e3631a474b7b5423f56e02207cc2be7d6112a63ff678efb9f09b07a1c66983a17a6a7fae85a114b80ca30ed701 04306ae0a0853ac8a40547d243e194146ea0df26b304795d3bfe7879507522120f4fa907593eed843987f91b52632a63b02b5aedbfec744e4fe0bc0b814ae11da1",
        "addresses": [
          "15djQ6BzrB766ovRzen3ReVtJzdfzDWwsk"
        ]
      }],
      "outputs": [
        {
          "amount": 1000,
          "spent": false,
          "script": "OP_DUP OP_HASH160 119b098e2e980a229e139a9ed01a469e518e6f26 OP_EQUALVERIFY OP_CHECKSIG",
          "script_hex": "76a914119b098e2e980a229e139a9ed01a469e518e6f2688ac",
          "script_type": "hash160",
          "addresses": [
            "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
          ]
        }
      ],
      "amount": 0,
      "fees": 0
    }
  ],
  "unconfirmed_transactions": [
    {
      "hash": "7f66c5e6a8bb4b9e640dfcb097232c740a43481dc02817959f48c48d3436b583",
      "version": 1,
      "lock_time": 0,
      "size": 258,
      "inputs": [],
      "outputs": [{
        "amount": 10000,
        "spent": false,
        "script": "OP_DUP OP_HASH160 119b098e2e980a229e139a9ed01a469e518e6f26 OP_EQUALVERIFY OP_CHECKSIG",
        "script_hex": "76a914119b098e2e980a229e139a9ed01a469e518e6f2688ac",
        "script_type": "hash160",
        "addresses": [
          "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
        ]
      }, {
        "amount": 732000,
        "spent": false,
        "script": "OP_DUP OP_HASH160 402319e566a996b9b512cb391352148c15b7a1f2 OP_EQUALVERIFY OP_CHECKSIG",
        "script_hex": "76a914402319e566a996b9b512cb391352148c15b7a1f288ac",
        "script_type": "hash160",
        "addresses": [
          "16r8J9bmThZCSN2qeKza6btdMk4bb8rnEh"
        ]
      }],
      "amount": 0,
      "fees": 0,
      "confirmations": 0,
      "pool": "orphan"
    }
  ]
}
```

This endpoint returns address balance and transactions

### HTTP Request

`GET https://network.coinbase.com/api/<version>/addresses/<hash>/transactions`

## Get address unspent outputs

```shell
curl "https://network.coinbase.com/api/v0/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX/unspent_outputs"
```

> The above command returns JSON structured like this:

~~~json
[
  {
    "transaction_hash": "24087a08309ea5796ef139e65f13ce10db1e4465057b665b9d5102a640aac6be",
    "output_index": 0,
    "amount": 1000,
    "script": "OP_DUP OP_HASH160 119b098e2e980a229e139a9ed01a469e518e6f26 OP_EQUALVERIFY OP_CHECKSIG",
    "script_hex": "76a914119b098e2e980a229e139a9ed01a469e518e6f2688ac",
    "script_type": "hash160",
    "addresses": [
      "12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
    ],
    "spent": false,
    "confirmations": 8304
  }
]
~~~


This endpoint returns address unspent outputs

### HTTP Request

`GET https://network.coinbase.com/api/<version>/addresses/<hash>/unspent_outputs`

# Websockets

## Subscribe to blocks

```json
{"subscribe":"blocks"}
```

> on new block returns JSON structured like this:

```json
{
  "subscription": "blocks",
  "data": {
    "hash": "0000000023197954763e1b17dc02a6823af1bbc79c12332bdd406e30ab0d2401",
    "branch": "main",
    "previous_block_hash": "000000003518748e59b2a48c13fc49755f84512a09903309a9d7c83733b4690f",
    "next_blocks": [],
    "height": 8640,
    "confirmations": 0,
    "merkle_root": "28fedcdf7dd35ad82f9e62b42baac65aaf27c97f187fa9a4fa802b0e07719826",
    "time": "2012-05-28T04:57:14Z",
    "created_at": "2014-09-10T06:25:20Z",
    "nonce": 2491172923,
    "bits": 473956288,
    "difficulty": 4,
    "reward": 5000000000,
    "fees": 0,
    "total_out": 5000000000,
    "size": 196,
    "transactions_count": 1,
    "version": 1,
    "transaction_hashes": [
      "28fedcdf7dd35ad82f9e62b42baac65aaf27c97f187fa9a4fa802b0e07719826"
    ]
  }
}
```

Receive notifications when a new block is found.

### Connection URL

`wss://network.coinbase.com`

## Subscribe to transactions

```json
{"subscribe":"transactions"}
```

> on new block returns JSON structured like this:

```json
{
  "subscription": "transactions",
  "data": {
    "hash": "4990c51b41e0f9986d31d6221ae651ede8833e27bbb1af079f6ef269541044b0",
    "version": 1,
    "lock_time": 0,
    "size": 223,
    "inputs": [],
    "outputs": [
      {
        "amount": 17971390,
        "spent": false,
        "script": "OP_DUP OP_HASH160 b5bd079c4d57cc7fc28ecf8213a6b791625b8183 OP_EQUALVERIFY OP_CHECKSIG",
        "script_hex": "76a914b5bd079c4d57cc7fc28ecf8213a6b791625b818388ac",
        "script_type": "hash160",
        "addresses": [
          "mx5u3nqdPpzvEZ3vfnuUQEyHg3gHd8zrrH"
        ]
      }
    ],
    "amount": 0,
    "fees": 0,
    "confirmations": 0,
    "pool": "orphan"
  }
}
```

Receive notifications when a new transactions is submited to the network.

### Connection URL

`wss://network.coinbase.com`

## Fetch latest block

```json
{"fetch":"latest_block"}
```

> on new block returns JSON structured like this:

```json
{
  "fetched": "latest_block",
  "data": {
    "hash": "4990c51b41e0f9986d31d6221ae651ede8833e27bbb1af079f6ef269541044b0",
    "version": 1,
    "lock_time": 0,
    "size": 223,
    "inputs": [],
    "outputs": [
      {
        "amount": 17971390,
        "spent": false,
        "script": "OP_DUP OP_HASH160 b5bd079c4d57cc7fc28ecf8213a6b791625b8183 OP_EQUALVERIFY OP_CHECKSIG",
        "script_hex": "76a914b5bd079c4d57cc7fc28ecf8213a6b791625b818388ac",
        "script_type": "hash160",
        "addresses": [
          "mx5u3nqdPpzvEZ3vfnuUQEyHg3gHd8zrrH"
        ]
      }
    ],
    "amount": 0,
    "fees": 0,
    "confirmations": 0,
    "pool": "orphan"
  }
}
```

Fetch latest block data.

### Connection URL

`wss://network.coinbase.com`

## Fetch latest transaction

```json
{"fetch":"latest_transaction"}
```

> on new block returns JSON structured like this:

```json
{
  "fetched": "latest_transaction",
  "data": {
    "hash": "4990c51b41e0f9986d31d6221ae651ede8833e27bbb1af079f6ef269541044b0",
    "version": 1,
    "lock_time": 0,
    "size": 223,
    "inputs": [],
    "outputs": [
      {
        "amount": 17971390,
        "spent": false,
        "script": "OP_DUP OP_HASH160 b5bd079c4d57cc7fc28ecf8213a6b791625b8183 OP_EQUALVERIFY OP_CHECKSIG",
        "script_hex": "76a914b5bd079c4d57cc7fc28ecf8213a6b791625b818388ac",
        "script_type": "hash160",
        "addresses": [
          "mx5u3nqdPpzvEZ3vfnuUQEyHg3gHd8zrrH"
        ]
      }
    ],
    "amount": 0,
    "fees": 0,
    "confirmations": 0,
    "pool": "orphan"
  }
}
```

Fetch latest submited transaction data.

### Connection URL

`wss://network.coinbase.com`
