// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXS: Promo Credit Settlement
// FEAT-UFXT: Settler Administration
// Shared test fixture: a settler over the real exchange and Conditional Tokens contracts, with a
// funded promo wallet, one registered market, a user Safe, and a house EOA. Test files import it.
// src/ never does.

import {ExchangeFixture} from "./ExchangeFixture.sol";
import {MockERC20} from "./MockERC20.sol";
import {PromoSettler} from "../../src/PromoSettler.sol";
import {Order, Side} from "exchange/libraries/OrderStructs.sol";

abstract contract PromoSettlerFixture is ExchangeFixture {
    /// @dev $10.00, the credit maximum every use case's preconditions name.
    uint128 internal constant MAX_CREDIT = 10_000_000;

    /// @dev $100.00 in the promo wallet, approved to the settler in full.
    uint256 internal constant PROMO_FUND = 100_000_000;

    /// @dev A promo code ID as the server writes it: bytes32(uint256(uint128(uuid))).
    bytes32 internal constant CODE = bytes32(uint256(uint128(0x5f0c8b8e2d3a4c1b9e7f6a5d4c3b2a19)));

    /// @dev The question ID of the one market every test trades.
    bytes32 internal constant MARKET = keccak256("promo-settler-market");

    /// @dev The user's Safe owner key and the house's EOA key, fixed so each test's addresses
    ///      are reproducible.
    uint256 internal constant USER_PK = 0xA11CE;
    uint256 internal constant HOUSE_PK = 0xB0B;

    MockERC20 internal usdc;
    PromoSettler internal settler;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal promoWallet = makeAddr("promo-wallet");
    address internal safe;
    address internal house;

    bytes32 internal conditionId;
    uint256 internal yesId;
    uint256 internal noId;

    /// @dev Deploys the stack, registers the settler and the operator on the exchange, funds and
    ///      approves the promo wallet, and gives the Safe and the house the approvals the real
    ///      wallets hold. The Safe approves the exchange at creation in production, so the test
    ///      pranks the Safe address to do the same.
    function setUp() public virtual {
        usdc = new MockERC20();
        _deployConditionalTokens();
        _deployExchange(address(usdc));
        (conditionId, yesId, noId) = _prepareBinaryCondition(MARKET, address(usdc));
        exchange.registerToken(yesId, noId, conditionId, MARKET);

        settler = new PromoSettler(address(exchange), promoWallet, admin, operator, MAX_CREDIT);
        exchange.addOperator(address(settler));
        exchange.addOperator(operator);

        usdc.mint(promoWallet, PROMO_FUND);
        vm.prank(promoWallet);
        usdc.approve(address(settler), PROMO_FUND);

        safe = exchange.getSafeAddress(vm.addr(USER_PK));
        vm.prank(safe);
        usdc.approve(address(exchange), type(uint256).max);

        house = vm.addr(HOUSE_PK);
        vm.startPrank(house);
        usdc.approve(address(exchange), type(uint256).max);
        ctf.setApprovalForAll(address(exchange), true);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    // Orders
    // ──────────────────────────────────────────────

    /// @dev The user's Safe BUY of `shares` of `tokenId` for `cost` USDC.
    function _userBuy(uint256 tokenId, uint256 cost, uint256 shares, uint256 feeRateBps)
        internal
        returns (Order memory)
    {
        return _safeOrder(USER_PK, tokenId, cost, shares, Side.BUY, feeRateBps);
    }

    /// @dev The house's SELL of `shares` of `tokenId` for `proceeds` USDC. The house first splits
    ///      `shares` USDC into complete sets, so it holds the shares it sells.
    function _houseSell(uint256 tokenId, uint256 shares, uint256 proceeds, uint256 feeRateBps)
        internal
        returns (Order memory)
    {
        _mintCompleteSets(usdc, house, conditionId, shares);
        return _eoaOrder(HOUSE_PK, tokenId, shares, proceeds, Side.SELL, feeRateBps);
    }

    /// @dev The house's BUY of `shares` of `tokenId` for `cost` USDC, funded with fresh USDC.
    function _houseBuy(uint256 tokenId, uint256 cost, uint256 shares, uint256 feeRateBps)
        internal
        returns (Order memory)
    {
        usdc.mint(house, cost);
        return _eoaOrder(HOUSE_PK, tokenId, cost, shares, Side.BUY, feeRateBps);
    }

    /// @dev Wraps one maker order and its fill amount.
    function _one(Order memory order, uint256 fillAmount)
        internal
        pure
        returns (Order[] memory orders, uint256[] memory fillAmounts)
    {
        orders = new Order[](1);
        orders[0] = order;
        fillAmounts = new uint256[](1);
        fillAmounts[0] = fillAmount;
    }

    // ──────────────────────────────────────────────
    // Settlement
    // ──────────────────────────────────────────────

    /// @dev Calls settle as the operator for the fixture's code, crediting the taker order.
    function _settleTaker(
        uint128 creditTotal,
        uint128 amount,
        Order memory takerOrder,
        Order memory makerOrder,
        uint256 takerFill,
        uint256 makerFill
    ) internal {
        (Order[] memory makers, uint256[] memory makerFills) = _one(makerOrder, makerFill);
        vm.prank(operator);
        settler.settle(CODE, creditTotal, amount, 0, takerOrder, makers, takerFill, makerFills);
    }

    /// @dev The credit record for the fixture's Safe and code.
    function _record() internal view returns (uint128 total, uint128 spent) {
        return settler.credits(safe, CODE);
    }
}
