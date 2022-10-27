#!/bin/bash

. lib.sh

REQ='{"network_identifier":{"blockchain":"mina","network":"debug"},"signatures":[{"hex_bytes": "251D96FE23D9195C65B77430CA0D326626009C28FDBE1AA47990C4235238A436C1B98ADACCEC9BB0BC7646C43A128BF83FC31B44CFC4F28BA7874489AFA7312B", "signature_type": "schnorr_poseidon", "public_key": { "curve_type": "tweedle", "hex_bytes": "xxx"}, "signing_payload": { hex_bytes: "xxx" }}], "unsigned_transaction": "{\"randomOracleInput\":\"0000000327EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B6567827EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B656785E6737A0AC0A147918437FC8C21EA57CECFB613E711CA2E4FD328401657C291C000002570029ACEE0000000080000000000000002000000000B48C8040500B531B1B7B00000000000000000000000000000000000000000000000000000006000000000000000001E82D3400000000\",\"signerInput\":{\"prefix\":[\"27EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B65678\",\"27EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B65678\",\"5E6737A0AC0A147918437FC8C21EA57CECFB613E711CA2E4FD328401657C291C\"],\"suffix\":[\"01BDB1B195A0140402625A0000000008000000000000000200000000EE6B2800\",\"0000000003000000000000000000000000000000000000000000000000000000\",\"000000000000000000000000000000000000000000000000059682F000000000\"]},\"payment\":{\"to\":\"B62qoDWfBZUxKpaoQCoFqr12wkaY84FrhxXNXzgBkMUi2Tz4K8kBDiv\",\"from\":\"B62qkUHaJUHERZuCHQhXCQ8xsGBqyYSgjQsKnKN5HhSJecakuJ4pYyk\",\"fee\":\"2000000000\",\"token\":\"1\",\"nonce\":\"2\",\"memo\":\"hello\",\"amount\":\"3000000000\",\"valid_until\":\"10000000\"},\"stakeDelegation\":null}"}'

# req '/construction/combine' '{"network_identifier":{"blockchain":"mina","network":"debug"},"signatures":[{"hex_bytes": "251D96FE23D9195C65B77430CA0D326626009C28FDBE1AA47990C4235238A436C1B98ADACCEC9BB0BC7646C43A128BF83FC31B44CFC4F28BA7874489AFA7312B", "signature_type": "schnorr_poseidon", "public_key": { "curve_type": "tweedle", "hex_bytes": "xxx"}, "signing_payload": { hex_bytes: "xxx" }}], "unsigned_transaction": "{\"randomOracleInput\":\"0000000327EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B6567827EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B656785E6737A0AC0A147918437FC8C21EA57CECFB613E711CA2E4FD328401657C291C000002570029ACEE0000000080000000000000002000000000B48C8040500B531B1B7B00000000000000000000000000000000000000000000000000000006000000000000000001E82D3400000000\",\"signerInput\":{\"prefix\":[\"27EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B65678\",\"27EA74CB13D3F1864C2E60C967577C055FD458D5AF93A59371905B8490B65678\",\"5E6737A0AC0A147918437FC8C21EA57CECFB613E711CA2E4FD328401657C291C\"],\"suffix\":[\"01BDB1B195A0140402625A0000000008000000000000000200000000EE6B2800\",\"0000000003000000000000000000000000000000000000000000000000000000\",\"000000000000000000000000000000000000000000000000059682F000000000\"]},\"payment\":{\"to\":\"B62qoDWfBZUxKpaoQCoFqr12wkaY84FrhxXNXzgBkMUi2Tz4K8kBDiv\",\"from\":\"B62qkUHaJUHERZuCHQhXCQ8xsGBqyYSgjQsKnKN5HhSJecakuJ4pYyk\",\"fee\":\"2000000000\",\"token\":\"1\",\"nonce\":\"2\",\"memo\":\"hello\",\"amount\":\"3000000000\",\"valid_until\":\"10000000\"},\"stakeDelegation\":null,\"createToken\":null,\"createTokenAccount\":null,\"mintTokens\":null}"}'


# REQ='{
#     "network_identifier": {
#         "blockchain": "bitcoin",
#         "network": "mainnet",
#         "sub_network_identifier": {
#             "network": "shard 1",
#             "metadata": {
#                 "producer": "0x52bc44d5378309ee2abf1539bf71de1b7d7be3b5"
#             }
#         }
#     },
#     "unsigned_transaction": "string",
#     "signatures": [
#         {
#             "signing_payload": {
#                 "address": "string",
#                 "account_identifier": {
#                     "address": "0x3a065000ab4183c6bf581dc1e55a605455fc6d61",
#                     "sub_account": {
#                         "address": "0x6b175474e89094c44da98b954eedeac495271d0f",
#                         "metadata": {}
#                     },
#                     "metadata": {}
#                 },
#                 "hex_bytes": "string",
#                 "signature_type": "ecdsa"
#             },
#             "public_key": {
#                 "hex_bytes": "string",
#                 "curve_type": "secp256k1"
#             },
#             "signature_type": "ecdsa",
#             "hex_bytes": "string"
#         }
#     ]
# }'

req '/construction/combine' "$REQ"
