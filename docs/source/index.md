---
title: API Reference

language_tabs:
  - shell

toc_footers:
  - <a href='http://github.com/tripit/slate'>Documentation Powered by Slate</a>

search: true
---

# Introduction

Welcome to the Toshi API! You can use our API to access Toshi API endpoints, which can get information on various blocks, transactions, and addresses in Toshi database.

# Blocks

## Get latest blocks

```shell
curl "http://toshi.io/api/blocks"
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

`GET http://toshi.io/api/blocks`

## Get latest block

```shell
curl "http://toshi.io/api/blocks/latest"
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

`GET http://toshi.io/api/blocks/latest`

## Get block by hash or height

```shell
curl "http://toshi.io/api/blocks/<hash or height>"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "00000...",
  "branch": "main",
  "previous_block_hash": "00000...",
  "next_blocks": [],
  "height": 307596,
  "confirmations": 0,
  "merkle_root": "aad54...",
  "time": "2014-06-24T17:11:39Z",
  "created_at": "2014-09-08T19:12:20Z",
  "nonce": 2876412913,
  "bits": 408005538,
  "difficulty": 13462580114.52535,
  "reward": 2500000000,
  "fees": 4953955,
  "total_out": 193727634504,
  "size": 214712,
  "transactions_count": 300,
  "version": 2,
  "transaction_hashes": [
    "ea59d...",
  ]
}
```

This endpoint retrieves block by hash or height.

### HTTP Request

`GET http://toshi.io/api/blocks/<hash or height>`

## Get block transactions

```shell
curl "http://toshi.io/api/blocks/<hash or height>/transactions"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "00000...",
  "branch": "main",
  "previous_block_hash": "00000...",
  "next_blocks": [
    {
      "hash": "00000...",
      "branch": "main",
      "height": 11
    }
  ],
  "height": 10,
  "confirmations": 308258,
  "merkle_root": "d3ad3...",
  "time": "2009-01-09T04:05:52Z",
  "created_at": "2014-09-05T01:01:27Z",
  "nonce": 1709518110,
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
      "hash": "d3ad3...",
      "version": 1,
      "lock_time": 0,
      "size": 134,
      "inputs": [
        {
          "previous_transaction_hash": "00000...",
          "output_index": 4294967295,
          "amount": 5000000000,
          "coinbase": "04ffff001d0136"
        }
      ],
      "outputs": [
        {
          "amount": 5000000000,
          "spent": false,
          "script": "04fcc...",
          "script_hex": "4104f...",
          "script_type": "pubkey",
          "addresses": [
            "15yN7NPEpu82sHhB6TzCW5z5aXoamiKeGy"
          ]
        }
      ],
      "amount": 5000000000,
      "fees": 0,
      "confirmations": 308258,
      "block_height": 10,
      "block_hash": "00000...",
      "block_time": "2009-01-09T04:05:52Z",
      "block_branch": "main"
    }
  ]
}
```

This endpoint retrieves latest block and full transactions list.

### HTTP Request

`GET http://toshi.io/api/blocks/<hash or height>/transactions`

# Transactions

## Get transaction

```shell
curl "http://toshi.io/api/transactions/<hash>"
```

> The above command returns JSON structured like this:

```json
{
  "hash": "2eaa7...",
  "version": 1,
  "lock_time": 0,
  "size": 157,
  "inputs": [
    {
      "previous_transaction_hash": "00000...",
      "output_index": 4294967295,
      "sequence": 0,
      "amount": 2500000000,
      "coinbase": "03c6b..."
    }
  ],
  "outputs": [
    {
      "amount": 2509020981,
      "spent": false,
      "script": "OP_DUP...",
      "script_hex": "76a91...",
      "script_type": "hash160",
      "addresses": [
        "1CjPR7Z5ZSyWk6WtXvSFgkptmpoi4UM9BC"
      ]
    }
  ],
  "amount": 2509020981,
  "fees": 0,
  "confirmations": 6,
  "block_height": 309958,
  "block_hash": "00000...",
  "block_time": "2014-07-09T17:09:48Z",
  "block_branch": "main"
}
```

This endpoint retrieves transaction information.

### HTTP Request

`GET http://toshi.io/api/transactions/<hash>`

## Relay transaction

```shell
curl https://toshi.io/api/transactions \
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

`GET http://toshi.io/api/transactions/<hash>`

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
curl "http://toshi.io/api/transactions/unconfirmed"
```

> The above command returns JSON structured like this:

```json
[
  {
    "hash": "33ba6...",
    "version": 1,
    "lock_time": 0,
    "size": 192,
    "inputs": [
      {
        "previous_transaction_hash": "3f1d2...",
        "output_index": 0,
        "amount": 5000000000,
        "script": "30450...",
        "addresses": [
          "1E3hS1LuZYgqqbzhSr87CQxoQWzcYb5XuA"
        ]
      }
    ],
    "outputs": [
      {
        "amount": 50000000,
        "spent": true,
        "script": "OP_DUP...",
        "script_hex": "76a91...",
        "script_type": "hash160",
        "addresses": [
          "1K37W5r7qSN2dWRYMv1PuXGSjoHgrVoieg"
        ]
      },
      {
        "amount": 4950000000,
        "spent": false,
        "script": "OP_DUP...",
        "script_hex": "76a91...",
        "script_type": "hash160",
        "addresses": [
          "1H53U7XocygtWd1dYv3YwgapfEHyoS94KH"
        ]
      }
    ],
    "amount": 5000000000,
    "fees": 0,
    "confirmations": 0,
    "pool": "memory"
  }
]
```

This endpoint returns a list of unconfirmed transactions

### HTTP Request

`GET http://toshi.io/api/addresses/<hash>`

# Addresses

## Get address balance

```shell
curl "http://toshi.io/api/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX"
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

`GET http://toshi.io/api/addresses/<hash>`

## Get address transactions

```shell
curl "http://toshi.io/api/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX/transactions"
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

`GET http://toshi.io/api/addresses/<hash>/transactions`

## Get address unspent outputs

```shell
curl "http://toshi.io/api/addresses/12c6DSiU4Rq3P4ZxziKxzrL5LmMBrzjrJX/unspent_outputs"
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

`GET http://toshi.io/api/addresses/<hash>/unspent_outputs`
