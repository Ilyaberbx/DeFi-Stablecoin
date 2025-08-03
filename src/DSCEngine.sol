//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine (Decentralized Stablecoin Engine)
 * @author Illia Verbanov
 * @notice This system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * @notice This contract is the core of DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This DSC System have to be "overcollateralized". The debt can never be greater than the value of all the collateral.
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__MustBeGreaterThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsMismatched();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsNotBroken();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintingFailed(address user, uint256 amount);
    error DSCEngine__HealthFactorIsNotImproved();
    error DSCEngine__InsufficientCollateral();
    error DSCEngine__InsufficientDsc();

    uint256 public constant MIN_HEALTH_FACTOR = 1;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant LIQUIDATION_BONUS = 10;
    uint256 public constant LIQUIDATION_BONUS_PRECISION = 100;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    /**
     * @notice Constructor
     * @param tokenAddresses The addresses of the tokens to be used as collateral
     * @param priceFeedAddresses The addresses of the price feeds to be used for each token
     * @param dscAddress The address of the DSC token
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsMismatched();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @notice Liquidates a user's position
     * @param tokenCollateral The address of the collateral token
     * @param user The address of the user to be liquidated
     * @param dscToBurnToImproveHealthFactor The amount of debt to cover
     * @notice You can partially liquidate a position, you don't have to liquidate the entire position
     * @notice You will get a liquidation bonus from liquidated user (10% of the value of the collateral)
     */
    function liquidate(address tokenCollateral, address user, uint256 dscToBurnToImproveHealthFactor) external isAllowedToken(tokenCollateral) moreThanZero(dscToBurnToImproveHealthFactor) nonReentrant {
        uint256 healthFactorBefore = _getHealthFactor(user);
        if (healthFactorBefore >= _getMinimumHealthFactor()) {
            revert DSCEngine__HealthFactorIsNotBroken();
        }

        uint256 tokenAmountFromDscToBurn = getTokenAmountFromUsd(tokenCollateral, dscToBurnToImproveHealthFactor);
        uint256 bonusCollateral = (tokenAmountFromDscToBurn * LIQUIDATION_BONUS) / LIQUIDATION_BONUS_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDscToBurn + bonusCollateral;

        _redeemCollateral(user, msg.sender, tokenCollateral, totalCollateralToRedeem);
        _burnDsc(dscToBurnToImproveHealthFactor, user, msg.sender);

        uint256 healthFactorAfter = _getHealthFactor(user);
        if (healthFactorAfter <= healthFactorBefore) {
            revert DSCEngine__HealthFactorIsNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Returns the health factor of the sender
     * @return The health factor of the sender
     */
    function getHealthFactor() external view returns (uint256) {
        return _getHealthFactor(msg.sender);
    }
    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token being deposited
     * @param amountCollateral The amount of the token being deposited
     * @param amountDscToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token being redeemed
     * @param amountCollateral The amount of the token being redeemed
     * @param amountDscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external moreThanZero(amountCollateral) moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /**
     * @notice Returns the amount of collateral deposited by a user
     * @param user The address of the user to get the deposited collateral of
     * @param tokenCollateralAddress The address of the token to get the deposited collateral of
     * @return The amount of collateral deposited by the user
     */
    function getDepositedCollateral(address user, address tokenCollateralAddress) external isAllowedToken(tokenCollateralAddress) view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    /**
     * @notice Returns the amount of DSC minted by a user
     * @param user The address of the user to get the minted DSC of
     * @return The amount of DSC minted by the user
     */
    function getDscMinted(address user) external view returns (uint256) {
        return s_dscMinted[user];
    }

    /**
     * @notice Returns the total amount of DSC minted and the total collateral value of the sender
     * @return totalDscMinted The total amount of DSC minted by the sender worth of USD
     * @return totalCollateralValueInUsd The total collateral value of the sender worth of USD
     */
    function getAccountInformation() external view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        return _getAccountInformation(msg.sender);
    }
    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token being redeemed
     * @param amountCollateral The amount of the token being redeemed
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    
    /**
     * @notice Returns true if the sender's health factor is broken
     * @return True if the sender's health factor is broken, false otherwise
     */
    function isHealthFactorBroken() external view returns (bool) {
        return _isHealthFactorBroken(msg.sender);
    }

    /**
     * @notice Returns the amount of tokens that are equivalent to the given USD amount
     * @param token The address of the token to get the amount of
     * @param usdAmountInWei The amount of USD in wei
     * @return The amount of tokens that are equivalent to the given USD amount
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }


    /**
     * @notice follows CEI pattern, burns DSC and reverts if health factor is broken
     * @param amountDscToBurn The amount of DSC to burn
     */
    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /** 
     * @notice follows CEI pattern
     * @param amountToMint The amount of DSC to mint, must be greater than 0
     */
    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountToMint);
        if (!success) {
            revert DSCEngine__MintingFailed(msg.sender, amountToMint);
        }
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token being deposited
     * @param amountCollateral The amount of the token being deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Returns the total collateral value of a user in USD
     * @param user The address of the user to get the collateral value of
     * @return totalCollateralValueInUsd The total collateral value of the user in USD
     */
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            if(amount <= 0){
                continue;
            }
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns the USD price of a token
     * @param token The address of the token to get the price of
     * @param amount The amount of the token to get the price of
     * @return The USD price of the token
     */
    function getUsdValue(address token, uint256 amount) public view moreThanZero(amount) returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice Burns DSC. Low level function that doesn't check health factor, so it should be used with caution
     * @param amountDscToBurn The amount of DSC to burn
     * @param onBehalfOf The address of the user who is burning the DSC
     * @param dscFrom The address of the user who is sending the DSC
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal moreThanZero(amountDscToBurn) {
        uint256 amountDscMinted = s_dscMinted[onBehalfOf];
        if (amountDscToBurn > amountDscMinted) {
            revert DSCEngine__InsufficientDsc();
        }
        
        s_dscMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    /**
     * @notice follows CEI pattern
     * @param from The address of the user who is redeeming the collateral
     * @param to The address of the user who is receiving the collateral
     * @param tokenCollateralAddress The address of the token being redeemed
     * @param amountCollateral The amount of the token being redeemed
     */
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) internal isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) {
        uint256 amountCollateralBefore = s_collateralDeposited[from][tokenCollateralAddress];
        if (amountCollateral > amountCollateralBefore) {
            revert DSCEngine__InsufficientCollateral();
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /** 
     * @notice Returns how close to liquidation a user is
     * @param user The address of the user to get the health factor of
     * @return The health factor of the user
     */
    function _getHealthFactor(address user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return PRECISION;
        }
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Returns the total amount of DSC minted and the total collateral value of a user
     * @param user The address of the user to get the account information of
     * @return totalDscMinted The total amount of DSC minted by the user worth of USD
     * @return totalCollateralValueInUsd The total collateral value of the user worth of USD
     */
    function _getAccountInformation(address user) internal view returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) {
        totalDscMinted = s_dscMinted[user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(user);
        return (totalDscMinted, totalCollateralValueInUsd);
    }

    /**
     * @notice Reverts if the health factor is broken
     * @param user The address of the user to check the health factor of
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < _getMinimumHealthFactor()) {
            revert DSCEngine__HealthFactorIsBroken(healthFactor);
        }
    }

    /**
     * @notice Returns the minimum health factor with precision ( 18 decimals )
     * @return The minimum health factor
     */
    function _getMinimumHealthFactor() internal pure returns (uint256) {
        return MIN_HEALTH_FACTOR * PRECISION;
    }
    /**
     * @notice Returns true if the health factor is broken
     * @param user The address of the user to check the health factor of
     * @return True if the health factor is broken, false otherwise
     */
    function _isHealthFactorBroken(address user) internal view returns (bool) {
        return _getHealthFactor(user) < _getMinimumHealthFactor();
    }
}
