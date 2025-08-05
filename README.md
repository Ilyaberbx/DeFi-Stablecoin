# DeFi Stablecoin (DSC) System

A decentralized, overcollateralized stablecoin system built on Ethereum, designed to maintain a $1.00 USD peg through algorithmic mechanisms and robust liquidation protocols.

## 🎯 Overview

The DeFi Stablecoin (DSC) system is a decentralized financial protocol that enables users to mint USD-pegged stablecoins by depositing cryptocurrency collateral. The system maintains stability through overcollateralization requirements and automated liquidation mechanisms.

### Key Properties

- **Relative Stability**: Anchored/Pegged to $1.00 USD
- **Stability Mechanism**: Algorithmic (Decentralized)
- **Collateral Type**: Exogenous (Crypto-backed)
- **Collateral Assets**: Wrapped Ethereum (wETH) and Wrapped Bitcoin (wBTC)
- **Overcollateralization**: Minimum 200% collateralization ratio (50% liquidation threshold)

### Smart Contracts

#### 1. DecentralizedStableCoin.sol

- **Type**: ERC20 token with additional minting/burning controls
- **Symbol**: DSC
- **Functionality**:
  - Standard ERC20 operations
  - Controlled minting (only by DSCEngine)
  - Enhanced burning with safety checks
  - Ownership-based access control

#### 2. DSCEngine.sol

- **Type**: Core protocol engine
- **Functionality**:
  - Collateral management (deposit/withdraw)
  - DSC minting and burning
  - Health factor calculations
  - Liquidation mechanism
  - Price feed integration (ChainLink)

#### 3. OracleLib.sol

- **Type**: Utility library
- **Functionality**:
  - Chainlink price feed integration
  - Stale price data protection (3-hour timeout)
  - Price validation and error handling

## ⚡ Key Features

### Overcollateralization System

- **Minimum Health Factor**: 1.0 (200%)
- **Liquidation Threshold**: 50% (200% collateralization required)
- **Liquidation Bonus**: 10% reward for liquidators

Example: 100$ WETH deposited with 50$ DSC minted is equals to 1.0 health factor, so system is overcollateralized to 200%

### Health Factor Calculation

```
Health Factor = (Collateral Value × Liquidation Threshold) / Total DSC Minted
```

- Health Factor < 1.0 = Liquidation eligible
- Health Factor ≥ 1.0 = Position is safe

### Security Features

- **Reentrancy Protection**: All external functions protected
- **CEI Pattern**: Checks-Effects-Interactions pattern implemented
- **Oracle Security**: Stale price feed detection and reversion
- **Access Control**: Ownership-based permissions
- **Input Validation**: Comprehensive parameter checking

## 🔧 Core Functions

### For Users

#### Deposit Collateral and Mint DSC

```solidity
function depositCollateralAndMintDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToMint
) external
```

#### Redeem Collateral for DSC

```solidity
function redeemCollateralForDsc(
    address tokenCollateralAddress,
    uint256 amountCollateral,
    uint256 amountDscToBurn
) external
```

#### Individual Operations

- `depositCollateral()` - Deposit collateral without minting
- `mintDsc()` - Mint DSC (requires sufficient collateral)
- `burnDsc()` - Burn DSC to improve health factor
- `redeemCollateral()` - Withdraw collateral

### For Liquidators

#### Liquidate Undercollateralized Positions

```solidity
function liquidate(
    address tokenCollateral,
    address user,
    uint256 dscToBurnToImproveHealthFactor
) external
```

- **Bonus**: 10% of liquidated collateral value
- **Requirement**: Target must have health factor < 1.0
- **Protection**: Liquidator's health factor verified post-liquidation

### View Functions

- `getHealthFactor()` - Check your health factor
- `getAccountInformation()` - Get DSC minted and collateral value
- `getAccountCollateralValueInUsd()` - Total collateral value in USD
- `getUsdValue()` - Convert token amount to USD value
- `getTokenAmountFromUsd()` - Convert USD amount to token amount

### Installation

```bash
git clone https://github.com/ilyaberbx/DeFi-Stablecoin.git
cd DeFi-Stablecoin
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy

#### Setup Environment Variables

Create a `.env` file (NEVER commit this file!):

```bash
# .env
SEPOLIA_PRIVATE_KEY=0x123abc...  # Your private key for Sepolia testnet
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_API_KEY
ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

#### Deploy to Sepolia

```bash
# Load environment variables and deploy
source .env
forge script script/DeployDSCSystem.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Or using --env-file flag
forge script script/DeployDSCSystem.s.sol --env-file .env --rpc-url $SEPOLIA_RPC_URL --broadcast
```

#### Deploy Locally (Anvil)

```bash
# Start local blockchain
anvil

# Deploy (in another terminal)
forge script script/DeployDSCSystem.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Production Deployment (Hardware Wallet - RECOMMENDED)

```bash
# Using Ledger hardware wallet for mainnet
forge script script/DeployDSCSystem.s.sol --rpc-url $MAINNET_RPC_URL --ledger --broadcast
```

## 📊 System Parameters

| Parameter             | Value      | Description                     |
| --------------------- | ---------- | ------------------------------- |
| Liquidation Threshold | 50%        | Minimum collateralization ratio |
| Liquidation Bonus     | 10%        | Reward for liquidators          |
| Min Health Factor     | 1.0        | Minimum allowed health factor   |
| Oracle Timeout        | 3 hours    | Maximum price feed staleness    |
| Supported Collateral  | wETH, wBTC | Accepted collateral tokens      |

## 🔒 Security Considerations

### Oracle Security

- **Chainlink Integration**: Reliable, decentralized price feeds
- **Stale Price Protection**: Automatic reversion on outdated data
- **Timeout Mechanism**: 3-hour maximum staleness

### Smart Contract Security

- **Reentrancy Guards**: Protection against reentrancy attacks
- **Integer Overflow**: Solidity 0.8+ built-in protection
- **Access Control**: Owner-only functions for critical operations
- **Input Validation**: Comprehensive parameter checking

### Private Key Security

⚠️ **CRITICAL**: Never commit private keys to version control!

- **Environment Variables**: Private keys stored in `.env` files (git-ignored)
- **Hardware Wallets**: Use Ledger/Trezor for production deployments
- **Key Management**: Separate keys for different environments (dev/test/prod)
- **Secure Defaults**: Use `vm.envOr()` with safe fallbacks

#### ✅ **Secure Setup**

```bash
# Create .env file (git-ignored)
echo "SEPOLIA_PRIVATE_KEY=0x123..." > .env
echo ".env" >> .gitignore

# Use environment variables in scripts
forge script --env-file .env --rpc-url $RPC_URL --broadcast
```

#### ❌ **Never Do This**

```solidity
// DON'T: Hardcode private keys in contracts
uint256 deployerKey = 0x123abc456def...;

// DON'T: Commit private keys to git
git add .env  // if .env contains private keys
```

### Economic Security

- **Overcollateralization**: 200% minimum backing reduces insolvency risk
- **Liquidation Incentives**: 10% bonus encourages timely liquidations
- **Health Factor System**: Transparent risk assessment

## 🧪 Testing

The project includes comprehensive test suites:

- **Unit Tests**: Individual contract functionality
- **Integration Tests**: Cross-contract interactions
- **Invariant Tests**: System-wide property verification
- **Fuzz Testing**: Property-based testing with random inputs

Run specific test types:

```bash
# Unit tests
forge test --match-path "test/unit/*"

# Integration tests
forge test --match-path "test/integration/*"

# Invariant tests
forge test --match-path "test/invariant/*"
```

## 📁 Project Structure

```
DeFi-Stablecoin/
├── src/
│   ├── DecentralizedStableCoin.sol    # ERC20 stablecoin contract
│   ├── DSCEngine.sol                  # Core engine contract
│   └── libraries/
│       └── OracleLib.sol             # Oracle utility library
├── script/
│   ├── DeployDSCSystem.s.sol         # Deployment script
│   └── config/
│       └── ConfigHelper.s.sol        # Network configuration
├── test/
│   ├── unit/                         # Unit tests
│   ├── integration/                  # Integration tests
│   ├── invariant/                    # Invariant tests
│   └── mocks/                        # Test mocks
└── lib/                              # Dependencies
```

## 🌐 Supported Networks

- Any EVM compatible network on the planet xd

## 📄 License

This project is licensed under the MIT License

## 🙏 Acknowledgments

- [OpenZeppelin](https://openzeppelin.com/) for secure smart contract libraries
- [Chainlink](https://chain.link/) for decentralized oracle infrastructure
- [Foundry](https://book.getfoundry.sh/) for development framework

## 📞 Contact

**Author**: Illia Verbanov

For questions, suggestions, or collaboration opportunities, please open an issue in this repository.

---

⚡ **Built with Solidity, Foundry, and powered by Chainlink Oracles**
