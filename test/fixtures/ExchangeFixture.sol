// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXS: Promo Credit Settlement
// UC-UFXV: Settle a Credited Trade
// Shared test fixture: the vendored bytecode of the exchange Prophet deploys, a stub Safe factory,
// and the helpers that sign a user's Safe order and a house EOA order. Adapted from lp-vaults'
// ExchangeFixture. Test files import it. src/ never does.

import {ConditionalTokensFixture} from "./ConditionalTokensFixture.sol";
import {Order, Side, SignatureType} from "exchange/libraries/OrderStructs.sol";

/// @dev The exchange functions the tests call directly, and the exchange errors a refused match
///      test expects.
interface IProphetCTFExchange {
    error NotCrossing();
    error NotTaker();
    error OrderFilledOrCancelled();

    event NewOperator(address indexed newOperatorAddress, address indexed admin);

    function setResolution(address resolution) external;
    function registerToken(uint256 token, uint256 complement, bytes32 conditionId, bytes32 questionId) external;
    function hashOrder(Order memory order) external view returns (bytes32);
    function cancelOrder(Order memory order) external;
    function addAdmin(address admin) external;
    function addOperator(address operator) external;
    function removeOperator(address operator) external;
    function isOperator(address addr) external view returns (bool);
    function getSafeAddress(address signer) external view returns (address);
    function getCollateral() external view returns (address);
    function getCtf() external view returns (address);
}

/// @dev Stands in for the Poly Safe factory. The exchange reads only `masterCopy()` from it and
///      derives each Safe by CREATE2 from that value, so nothing else is needed. The Safe's own
///      code plays no part in a settlement, because the exchange only pulls from the Safe address.
contract StubSafeFactory {
    address public immutable masterCopy;

    constructor(address masterCopy_) {
        masterCopy = masterCopy_;
    }
}

/// @dev Base for every test that settles a match. The artifact is `ProphetCTFExchange` from
///      ProphetMarket/contracts at commit b5903f1 ("Deploy to mainnet"), vendored from lp-vaults'
///      test/artifacts. Its bytecode matches the Polygon exchange at
///      0x127aD3A6e55EbBDaecC0eaeb12615879611e1839 up to the metadata hash. The exchange compiles
///      with solc 0.8.31 and this repository with 0.8.24, so the artifact is deployed, not
///      compiled.
abstract contract ExchangeFixture is ConditionalTokensFixture {
    /// @dev Vendored forge artifact. foundry.toml grants read access.
    string internal constant EXCHANGE_ARTIFACT = "test/artifacts/ProphetCTFExchange.json";

    IProphetCTFExchange internal exchange;
    StubSafeFactory internal safeFactory;

    /// @dev Makes every order's salt unique, so two orders with the same terms hash differently.
    uint256 private _saltNonce;

    /// @dev Deploys the real exchange bytecode over `usdc`, the fixture's Conditional Tokens
    ///      contract, and a stub Safe factory. The deployer (this test contract) is the
    ///      exchange's admin and operator, by the Auth constructor. `resolution` is this test
    ///      contract, because _prepareBinaryCondition prepares each condition with the test
    ///      contract as the Conditional Tokens oracle, and registerToken checks that.
    function _deployExchange(address usdc) internal {
        safeFactory = new StubSafeFactory(makeAddr("safe-master-copy"));
        exchange = IProphetCTFExchange(
            deployCode(EXCHANGE_ARTIFACT, abi.encode(usdc, address(ctf), address(0), address(safeFactory)))
        );
        exchange.setResolution(address(this));
    }

    /// @dev A Safe order: `side` of `tokenId`, `makerAmount` for `takerAmount`, signed by the
    ///      Safe's owner key `ownerPk`. `maker` is the Safe the exchange derives from the owner,
    ///      and `signatureType = POLY_GNOSIS_SAFE`, the shape every Prophet user order has.
    function _safeOrder(
        uint256 ownerPk,
        uint256 tokenId,
        uint256 makerAmount,
        uint256 takerAmount,
        Side side,
        uint256 feeRateBps
    ) internal returns (Order memory order) {
        address owner = vm.addr(ownerPk);
        order = _unsignedOrder(exchange.getSafeAddress(owner), owner, tokenId, makerAmount, takerAmount, side);
        order.feeRateBps = feeRateBps;
        order.signatureType = SignatureType.POLY_GNOSIS_SAFE;
        order.signature = _signOrder(ownerPk, order);
    }

    /// @dev An EOA order, signed by `pk` as both maker and signer. The house signs this shape.
    function _eoaOrder(
        uint256 pk,
        uint256 tokenId,
        uint256 makerAmount,
        uint256 takerAmount,
        Side side,
        uint256 feeRateBps
    ) internal returns (Order memory order) {
        address eoa = vm.addr(pk);
        order = _unsignedOrder(eoa, eoa, tokenId, makerAmount, takerAmount, side);
        order.feeRateBps = feeRateBps;
        order.signatureType = SignatureType.EOA;
        order.signature = _signOrder(pk, order);
    }

    /// @dev Signs `order` over the exchange's hashOrder with `pk`, as `r || s || v`. A test that
    ///      edits a signed field calls this again, so the exchange sees a valid signature and
    ///      rejects the order for the edited field only.
    function _signOrder(uint256 pk, Order memory order) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, exchange.hashOrder(order));
        return abi.encodePacked(r, s, v);
    }

    function _unsignedOrder(
        address maker,
        address signer,
        uint256 tokenId,
        uint256 makerAmount,
        uint256 takerAmount,
        Side side
    ) private returns (Order memory order) {
        order = Order({
            salt: ++_saltNonce,
            maker: maker,
            signer: signer,
            taker: address(0),
            tokenId: tokenId,
            makerAmount: makerAmount,
            takerAmount: takerAmount,
            expiration: 0,
            nonce: 0,
            feeRateBps: 0,
            side: side,
            signatureType: SignatureType.EOA,
            signature: ""
        });
    }
}
