# ARB-RAAS
Arbitrum Rollup scripts


when  executing testnet  and  devnet  in the same env 

```sh
./test-node-testnet.bash --init 

./test-node-devnet.bash --init 
```


Stop and  remove all containers and remove or prune volumes to not have old genesis  config  present for previous config...

```sh
docker volume rm nitro-testnode_config nitro-testnode_l1data nitro-testnode_l1keystore nitro-testnode_tokenbridge-data testnet_config testnet_l1data testnet_l1keystore testnet_seqdata testnet_to kenbridge-data
```

## Named accounts

```bash
./test-node.bash script print-address --account sequencer
```
```
sequencer:                  0xe2148eE53c0755215Df69b2616E552154EdC584f
validator:                  0x6A568afe0f82d34759347bb36F14A6bB171d2CBe
l2owner:                    0x5E1497dD1f08C87b2d8FE23e9AAB6c1De833D927
l3owner:                    0x863c904166E801527125D8672442D736194A3362
l3sequencer:                0x3E6134aAD4C4d422FF2A4391Dc315c4DDf98D1a5
user_l1user:                0x058E6C774025ade66153C65672219191c72c7095
user_token_bridge_deployer: 0x3EaCb30f025630857aDffac9B2366F953eFE4F98
user_fee_token_deployer:    0x2AC5278D230f88B481bBE4A94751d7188ef48Ca2
```

While not a named account, 0x3f1eae7d46d88f08fc2f8ed27fcb2ab183eb2d0e is funded on all test chains.

