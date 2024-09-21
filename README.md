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
- forge install smartcontractkit/chainlink-brownie-contracts@1.2.0 --no-commit

## Commands
- forge inspect DSCEngine methods
    - prints all the methods in this contract

## Test
- forge test
- forge test --match-test testRevertsIfCollateralZero
- forge test --match-test testRevertsIfCollateralZero -vvvv
- forge test --match-test testRevertsIfCollateralZero -vv
- forge test --fork-url $SEPOLIA_RPC_URL
- forge coverage
- forge coverage --report debug
    - To view the line items to add tests
 


## VSCode Setup
    - Install Solidity(Nomic) extension 
        - Change the format settings to forge 
    - Install codeium extension in VSCode for AI Pair programming

## 
- Natspec Documenation
- reentrant
- indexed keyword in event
- IERC20 - transfer vs transferFrom
- memory vs storage 

## 
- Fuzz Testing : 
    - Random data to one function 
    - Fuzzing = Stateless Fuzzing
- Invariant Tests : 
    - Random data and Random functional calls to many functions
    - Invariant = Stateful Fuzzing 
- Invariant : 
    - property of our system that should always hold. 
- invariant tests : 
    - Stateful Fuzzing 



## Issues: 
- openzeppelin contracts import issue in vscode 
    - https://github.com/Cyfrin/foundry-full-course-cu/discussions/1780#discussioncomment-9651251
- invariant test failing to setup
    - Execute these commands ( Could be a cache issue)
    - foundryup 
    - forge clean 

## References: 
- https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=ETH+%2F+USD
- Health Factor Calculation 
    - https://github.com/Cyfrin/foundry-full-course-cu/discussions/368#discussioncomment-6478351
- Aave Liquidation Calculation/ Health 
    - https://docs.aave.com/developers/guides/liquidations
    - https://chatgpt.com/share/66e345d6-c8fc-8008-b86d-d90a10586c5c
- Test 
    - Expect uint256 overflow/underflow error 
        - https://chatgpt.com/share/66e58e08-3c90-8008-b0c6-08e9bacd7b14
- Invariant Testing 
    - https://book.getfoundry.sh/forge/invariant-testing
- Audit Readiness Checklist 
    - https://github.com/nascentxyz/simple-security-toolkit/blob/main/audit-readiness-checklist.md
- Social Platform like Twitter - To integrate contracts 
    - https://www.lens.xyz/docs

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
