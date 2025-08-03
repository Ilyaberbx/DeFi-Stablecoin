//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSCSystem} from "../../script/DeployDSCSystem.s.sol";
import {ConfigHelper} from "../../script/config/ConfigHelper.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.t.sol";
import {console} from "forge-std/console.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.t.sol";

contract DSCEngineTests is Test {

    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    DSCEngine private s_engine;
    DecentralizedStableCoin private s_dsc;
    ConfigHelper private s_configHelper;
    address private s_weth;
    address private s_wbtc;
    address private s_wethUsdPriceFeed;
    address private s_wbtcUsdPriceFeed;
    uint256 private s_deployerKey;
    address private s_user = makeAddr("user");
    address private s_liquidator = makeAddr("liquidator");

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    modifier depositedCollateral(address user, address collateral, uint256 amount) {
        vm.startPrank(user);
        ERC20Mock(collateral).approve(address(s_engine), amount);
        s_engine.depositCollateral(collateral, amount);
        console.log("Deposited collateral: ", s_engine.getDepositedCollateral(user, collateral));
        vm.stopPrank();
        _;
    }

    function setUp() public {
        DeployDSCSystem deployer = new DeployDSCSystem();
        (s_dsc, s_engine, s_configHelper) = deployer.run();
        (s_wethUsdPriceFeed, s_wbtcUsdPriceFeed, s_weth, s_wbtc, s_deployerKey) = s_configHelper.s_activeNetworkConfig();
        ERC20Mock(s_weth).mint(s_user, AMOUNT_COLLATERAL);
        ERC20Mock(s_wbtc).mint(s_user, AMOUNT_COLLATERAL);
        ERC20Mock(s_weth).mint(s_liquidator, AMOUNT_COLLATERAL * 3);
        ERC20Mock(s_wbtc).mint(s_liquidator, AMOUNT_COLLATERAL * 3);
    }

    /* Price Feeds */

    function testGetUsdValueFromToken() public view {
        uint256 amountWeth = 100 ether;
        uint256 amountWbtc = 100 ether;
        uint256 expectedWethValue = 2000 * amountWeth;
        uint256 expectedWbtcValue = 2000 * amountWbtc;
        console.log("weth: ", s_weth);
        console.log("wbtc: ", s_wbtc);
        console.log("amountWeth: ", amountWeth);
        console.log("amountWbtc: ", amountWbtc);
        console.log("expectedWethValue: ", expectedWethValue);
        console.log("expectedWbtcValue: ", expectedWbtcValue);
        assertEq(s_engine.getUsdValue(s_weth, amountWeth), expectedWethValue);
        assertEq(s_engine.getUsdValue(s_wbtc, amountWbtc), expectedWbtcValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 1000 ether;
        uint256 expectedWethAmount = 0.5 ether;
        uint256 actualWethAmount = s_engine.getTokenAmountFromUsd(s_weth, usdAmount);
        assertEq(actualWethAmount, expectedWethAmount);
    }

    function testChangingAnswerForPriceFeedIsSuccessful() public {
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        assertEq(mockPriceFeed.latestAnswer(), 2000e8);
        mockPriceFeed.updateAnswer(1000e8);
        assertEq(mockPriceFeed.latestAnswer(), 1000e8);
    }

    function testChangingAnswerForPriceFeedAffectsAccountInformation() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        uint256 dscToMint = 1000 ether;
        s_engine.mintDsc(dscToMint);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = s_engine.getAccountInformation();
        uint256 expectedTotalCollateralValueInUsd = (AMOUNT_COLLATERAL * 2000e8 * 1e10) / 1e18;
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);
        assertEq(totalDscMinted, dscToMint);
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        mockPriceFeed.updateAnswer(1000e8);
        (totalDscMinted, totalCollateralValueInUsd) = s_engine.getAccountInformation();
        expectedTotalCollateralValueInUsd = (AMOUNT_COLLATERAL * 1000e8 * 1e10) / 1e18;
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);
        assertEq(totalDscMinted, dscToMint);
        vm.stopPrank();
    }

    function testChangingAnswerBreaksHealthFactor() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(5000 ether);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = s_engine.getAccountInformation();
        console.log("totalDscMinted: ", totalDscMinted);
        console.log("totalCollateralValueInUsd: ", totalCollateralValueInUsd);
        console.log("Health factor: ", s_engine.getHealthFactor());
        assertFalse(s_engine.isHealthFactorBroken());
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        mockPriceFeed.updateAnswer(999e8);
        (totalDscMinted, totalCollateralValueInUsd) = s_engine.getAccountInformation();
        console.log("totalDscMinted: ", totalDscMinted);
        console.log("totalCollateralValueInUsd: ", totalCollateralValueInUsd);
        console.log("Health factor: ", s_engine.getHealthFactor());
        assertTrue(s_engine.isHealthFactorBroken());
        vm.stopPrank();
    }
 
    /* Deposit */

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = s_engine.getAccountInformation();
        uint256 collateralDeposited = s_engine.getTokenAmountFromUsd(s_weth, totalCollateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(AMOUNT_COLLATERAL, collateralDeposited);
        vm.stopPrank();
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(s_user);
        ERC20Mock(s_weth).approve(address(s_engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(s_user, s_weth, AMOUNT_COLLATERAL);
        s_engine.depositCollateral(s_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositlCollateralAndMintDscIsCorrect() public {
        vm.startPrank(s_user);
        ERC20Mock(s_weth).approve(address(s_engine), AMOUNT_COLLATERAL);
        s_engine.depositCollateralAndMintDsc(s_weth, AMOUNT_COLLATERAL, 1000 ether);
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = s_engine.getAccountInformation();
        uint256 expectedTotalCollateralValueInUsd = (AMOUNT_COLLATERAL * 2000e8 * 1e10) / 1e18;
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd);
        assertEq(totalDscMinted, 1000 ether);
        vm.stopPrank();
    }

    /* Liquidation */

    function testLiquidationImprovesHealthFactor() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) depositedCollateral(s_liquidator, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(10000 ether);
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        mockPriceFeed.updateAnswer(1500e8); 
        uint256 healthFactorBefore = s_engine.getHealthFactor();
        uint256 dscToBurnToImproveHealthFactor = 1000 ether;
        vm.stopPrank();
        vm.startPrank(s_liquidator);
        s_dsc.approve(address(s_engine), dscToBurnToImproveHealthFactor);
        s_engine.mintDsc(dscToBurnToImproveHealthFactor);
        s_engine.liquidate(s_weth, s_user, dscToBurnToImproveHealthFactor);
        vm.stopPrank();
        vm.prank(s_user);
        uint256 healthFactorAfter = s_engine.getHealthFactor();
        assertGt(healthFactorAfter, healthFactorBefore);
    }

    /* Redeem Collateral */
    
    function testRedeemCollateralIsSuccessful() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        uint256 depositedColalteralBefore = s_engine.getDepositedCollateral(s_user, s_weth);
        vm.startPrank(s_user);
        s_engine.redeemCollateral(s_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(depositedColalteralBefore, AMOUNT_COLLATERAL);
        assertEq(s_engine.getDepositedCollateral(s_user, s_weth), 0);
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(s_user, s_user, s_weth, AMOUNT_COLLATERAL);
        s_engine.redeemCollateral(s_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscIsSuccessful() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        uint256 depositedColalteralBefore = s_engine.getDepositedCollateral(s_user, s_weth);
        vm.startPrank(s_user);
        s_dsc.approve(address(s_engine), 1000 ether);
        s_engine.mintDsc(1000 ether);
        s_engine.redeemCollateralForDsc(s_weth, AMOUNT_COLLATERAL, 1000 ether);
        vm.stopPrank();
        assertEq(depositedColalteralBefore, AMOUNT_COLLATERAL);
        assertEq(s_engine.getDepositedCollateral(s_user, s_weth), 0);
    }
    
    /* Account Collateral Value */

    function testGetAccountCollateralValueInUsdWithOneCollateralDeposited() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        uint256 expectedCollateralValueInUsd = AMOUNT_COLLATERAL * 2000e8 * 1e10 / 1e18;
        assertEq(s_engine.getAccountCollateralValueInUsd(s_user), expectedCollateralValueInUsd);
    }

    function testGetAccountCollateralValueInUsdWithMultipleCollaterals() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) depositedCollateral(s_user, s_wbtc, AMOUNT_COLLATERAL) {
        uint256 expectedCollateralValueInUsd = (AMOUNT_COLLATERAL * 2000e8 * 1e10) / 1e18 + (AMOUNT_COLLATERAL * 2000e8 * 1e10) / 1e18;
        assertEq(s_engine.getAccountCollateralValueInUsd(s_user), expectedCollateralValueInUsd);
    }

    /* Reverts */

    function testConstructorRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        address[] memory tokens = new address[](2);
        tokens[0] = s_weth;
        tokens[1] = s_wbtc;
        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = s_wethUsdPriceFeed;
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsMismatched.selector);
        new DSCEngine(tokens, priceFeeds, address(s_dsc));
    }

    function testRedeemCollateralRevertsIfTokenIsNotAllowed() public {
        ERC20Mock dummyCollateralToken = new ERC20Mock("Dummy", "DUMMY", s_user, AMOUNT_COLLATERAL);
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        s_engine.redeemCollateral(address(dummyCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfAmountIsZero() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        s_engine.redeemCollateral(s_weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfUserDoesNotHaveEnoughCollateral() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientCollateral.selector);
        s_engine.redeemCollateral(s_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfHealthFactorIsBroken() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(10000 ether);
        console.log("Health factor: ", s_engine.getHealthFactor());
        uint256 expectedHealthFactor = 9e17;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor));
        s_engine.redeemCollateral(s_weth, 1 ether);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsIfCollateralZero() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        s_engine.depositCollateral(s_weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsIfTokenIsNotAllowed() public {
        ERC20Mock dummyCollateralToken = new ERC20Mock("Dummy", "DUMMY", s_user, AMOUNT_COLLATERAL);
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        s_engine.depositCollateral(address(dummyCollateralToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintDscRevertsIfDscToMintIsZero() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        s_engine.mintDsc(0);
        vm.stopPrank();
    }
    
    function testBurnDscRevertsIfDscToBurnIsZero() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        s_engine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfUserDoesNotHaveEnoughDsc() public {
        vm.startPrank(s_user);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientDsc.selector);
        s_engine.burnDsc(1 ether);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfHealthFactorIsBroken() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(10000 ether);
        console.log("Health factor: ", s_engine.getHealthFactor());
        s_dsc.approve(address(s_engine), 1000 ether);
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        mockPriceFeed.updateAnswer(1000e8);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 555555555555555555));
        s_engine.burnDsc(1000 ether);
        console.log("Health factor: ", s_engine.getHealthFactor());
        vm.stopPrank();
    }

    function testLiquidationRevertsIfDscToBurnToImproveHealthFactorIsZero() public {
        vm.startPrank(s_liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        s_engine.liquidate(s_weth, s_user, 0);
        vm.stopPrank();
    }

    function testLiquidationRevertsIfHealthFactorIsNotBroken() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(10000 ether);
        console.log("Health factor: ", s_engine.getHealthFactor());
        vm.stopPrank();
        vm.startPrank(s_liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        s_engine.liquidate(s_weth, s_user, 100 ether);
        vm.stopPrank();
    }

    function testLiquidationRevertsIfTokenIsNotAllowed() public {
        ERC20Mock dummyCollateralToken = new ERC20Mock("Dummy", "DUMMY", s_user, AMOUNT_COLLATERAL);
        vm.startPrank(s_liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        s_engine.liquidate(address(dummyCollateralToken), s_user, 100 ether);
        vm.stopPrank();
    }

    function testLiquidationRevertsIfLiquidatorIsBrokenAfterLiquidation() public depositedCollateral(s_user, s_weth, AMOUNT_COLLATERAL) depositedCollateral(s_liquidator, s_weth, AMOUNT_COLLATERAL) {
        vm.startPrank(s_user);
        s_engine.mintDsc(10000 ether);
        vm.stopPrank();
        vm.startPrank(s_liquidator);
        s_dsc.approve(address(s_engine), 10000 ether);
        s_engine.mintDsc(10000 ether);
        MockV3Aggregator mockPriceFeed = MockV3Aggregator(s_wethUsdPriceFeed);
        mockPriceFeed.updateAnswer(1500e8);
        uint256 liquidatorHealthFactor = s_engine.getHealthFactor();
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, liquidatorHealthFactor));
        s_engine.liquidate(s_weth, s_user, 10000 ether);
        vm.stopPrank();
    }   
}