## Stablecoin 

1. Relative Stability : Anchored or Pegged -> $1.00
    1. Chainlink Price Feed 
    2. Set a function to exchange ETH & BTC -> $$$
2. Stability Mechanism(Minting) : Algorithmic ( Decentralized )
    1. People can only mint the stable coin with enough collateral (coded)
3. Collateral Type : Exogenous (Crypto)
    1. wETH 
    2. wBTC 


## Setup 
- forge init 
- forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit

## Issues: 
- openzeppelin contracts import issue in vscode 
    - https://github.com/Cyfrin/foundry-full-course-cu/discussions/1780#discussioncomment-9651251


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
