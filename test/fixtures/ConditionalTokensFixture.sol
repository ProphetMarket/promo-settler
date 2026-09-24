// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXS: Promo Credit Settlement
// Shared test fixture: the real Gnosis ConditionalTokens bytecode and the helpers that prepare a
// binary condition and split USDC into outcome shares. Adapted from lp-vaults'
// ConditionalTokensFixture. Test files import it. src/ never does.

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev The ConditionalTokens functions the tests call directly. The settler reaches the same
///      contract through the inline interface in src/PromoSettler.sol.
interface ITestConditionalTokens {
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external;
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32);
    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        view
        returns (bytes32);
    function getPositionId(address collateralToken, bytes32 collectionId) external pure returns (uint256);
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function setApprovalForAll(address operator, bool approved) external;
}

/// @dev Base for every test that trades outcome shares. The exchange mints, pays, and charges
///      fees through the real ConditionalTokens contract, so a mock would test the mock.
abstract contract ConditionalTokensFixture is Test {
    /// @dev Vendored build of the Gnosis ConditionalTokens contract, pinned by the ctf-exchange
    ///      submodule. foundry.toml grants read access to this folder.
    string internal constant CONDITIONAL_TOKENS_ARTIFACT = "lib/ctf-exchange/artifacts/ConditionalTokens.json";

    ITestConditionalTokens internal ctf;

    /// @dev Deploys the real ConditionalTokens bytecode and keeps it in `ctf`.
    function _deployConditionalTokens() internal returns (ITestConditionalTokens) {
        ctf = ITestConditionalTokens(deployCode(CONDITIONAL_TOKENS_ARTIFACT));
        return ctf;
    }

    /// @dev Prepares a 2-outcome condition with this test contract as the condition's oracle.
    ///      Index set 1 is YES and index set 2 is NO.
    function _prepareBinaryCondition(bytes32 questionId, address collateral)
        internal
        returns (bytes32 conditionId, uint256 yesTokenId, uint256 noTokenId)
    {
        ctf.prepareCondition(address(this), questionId, 2);
        conditionId = ctf.getConditionId(address(this), questionId, 2);
        yesTokenId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 1));
        noTokenId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 2));
    }

    /// @dev Gives `holder` `amount` YES and `amount` NO by splitting fresh USDC through the real
    ///      contract.
    function _mintCompleteSets(MockERC20 usdc, address holder, bytes32 conditionId, uint256 amount) internal {
        usdc.mint(holder, amount);
        vm.startPrank(holder);
        usdc.approve(address(ctf), amount);
        ctf.splitPosition(address(usdc), bytes32(0), conditionId, _binaryPartition(), amount);
        vm.stopPrank();
    }

    /// @dev The partition [1, 2]: YES then NO.
    function _binaryPartition() internal pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }
}
