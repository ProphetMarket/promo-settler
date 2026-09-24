// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// UC-UFXW: Manage Settler Roles
// T-002: The admin manages the settler's admins and operators
// Integration tests driven through the settler's role functions. The registry is the lp-vaults
// factory registry without the oracle role, so these tests pin the same behavior.

import {Test} from "forge-std/Test.sol";
import {PromoSettler} from "../../../src/PromoSettler.sol";
import {Order} from "exchange/libraries/OrderStructs.sol";

/// @dev Answers the two reads the settler's constructor makes, and lists no exchange operator.
///      Role management never reaches a match, so these tests need no market. A settle call from
///      a settler operator therefore stops at the exchange-operator check, which proves that the
///      settler's own operator check let it through.
contract ExchangeAddressStub {
    address public immutable collateral;
    address public immutable ctf;

    constructor(address collateral_, address ctf_) {
        collateral = collateral_;
        ctf = ctf_;
    }

    function getCollateral() external view returns (address) {
        return collateral;
    }

    function getCtf() external view returns (address) {
        return ctf;
    }

    function isOperator(address) external pure returns (bool) {
        return false;
    }
}

contract ManageSettlerRolesTest is Test {
    PromoSettler internal settler;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal stranger = makeAddr("stranger");
    address internal newcomer = makeAddr("newcomer");

    function setUp() public {
        ExchangeAddressStub exchange = new ExchangeAddressStub(makeAddr("usdc"), makeAddr("ctf"));
        settler = new PromoSettler(address(exchange), makeAddr("promo-wallet"), admin, operator, 10_000_000);
    }

    // ──────────────────────────────────────────────
    // SC-UFYF: A caller outside the admins is refused
    // ──────────────────────────────────────────────

    // SC-UFYF: A caller outside the admins is refused
    //
    // Role changes are the most sensitive calls in the contract. Every one of the six reverts
    // with NotAdmin for an address with admins(address) = 0, and the registry keeps its values.
    function test_callerOutsideTheAdminsCannotChangeRoles() public {
        vm.startPrank(stranger);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.addAdmin(stranger);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.removeAdmin(admin);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.renounceAdminRole();
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.transferAdmin(stranger);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.addOperator(stranger);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.removeOperator(operator);
        vm.stopPrank();

        assertEq(settler.adminCount(), 1);
        assertEq(settler.admins(admin), 1);
        assertEq(settler.admins(stranger), 0);
        assertEq(settler.operators(operator), 1);
        assertEq(settler.pendingAdmin(), address(0));
    }

    // ──────────────────────────────────────────────
    // SC-UFYG: The admin adds and removes an operator
    // ──────────────────────────────────────────────

    // SC-UFYG: The admin adds and removes an operator
    //
    // The operator set decides who may call settle. Each change writes the mapping and emits
    // its event with the admin as the second topic.
    function test_adminAddsAndRemovesAnOperator() public {
        vm.expectEmit(address(settler));
        emit PromoSettler.NewOperator(newcomer, admin);
        vm.prank(admin);
        settler.addOperator(newcomer);
        assertEq(settler.operators(newcomer), 1);
        // The settler's operator check lets P through: the call stops at the next check.
        _expectSettleRevert(newcomer, PromoSettler.NotExchangeOperator.selector);

        vm.expectEmit(address(settler));
        emit PromoSettler.RemovedOperator(newcomer, admin);
        vm.prank(admin);
        settler.removeOperator(newcomer);
        assertEq(settler.operators(newcomer), 0);
        _expectSettleRevert(newcomer, PromoSettler.NotOperator.selector);
    }

    /// @dev Calls settle as `caller` with empty orders and expects `selector`. The modifiers run
    ///      before the body reads any order, so empty orders reach every role check.
    function _expectSettleRevert(address caller, bytes4 selector) internal {
        Order memory none;
        vm.prank(caller);
        vm.expectRevert(selector);
        settler.settle(bytes32(0), 1, 1, 0, none, new Order[](0), 1, new uint256[](0));
    }

    // ──────────────────────────────────────────────
    // SC-UFYH: The admin adds and removes an admin
    // ──────────────────────────────────────────────

    // SC-UFYH: The admin adds and removes an admin
    //
    // adminCount counts each admin once. A repeated add still emits NewAdmin but keeps the count
    // at 2, and a removal brings it back to 1.
    function test_adminAddsAndRemovesAnAdmin() public {
        vm.startPrank(admin);
        vm.expectEmit(address(settler));
        emit PromoSettler.NewAdmin(newcomer, admin);
        settler.addAdmin(newcomer);
        assertEq(settler.admins(newcomer), 1);
        assertEq(settler.adminCount(), 2);

        vm.expectEmit(address(settler));
        emit PromoSettler.NewAdmin(newcomer, admin);
        settler.addAdmin(newcomer);
        assertEq(settler.adminCount(), 2);

        vm.expectEmit(address(settler));
        emit PromoSettler.RemovedAdmin(newcomer, admin);
        settler.removeAdmin(newcomer);
        assertEq(settler.admins(newcomer), 0);
        assertEq(settler.adminCount(), 1);
        vm.stopPrank();
    }

    // SC-UFYH: The zero address cannot become an admin
    function test_zeroAddressCannotBecomeAnAdmin() public {
        vm.prank(admin);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        settler.addAdmin(address(0));
        assertEq(settler.adminCount(), 1);
    }

    // ──────────────────────────────────────────────
    // SC-UFYI: The last admin cannot leave
    // ──────────────────────────────────────────────

    // SC-UFYI: The last admin cannot leave
    //
    // A settler with no admin could never be paused or reconfigured, so both exits revert while
    // adminCount = 1. With a second admin present, the first admin may renounce.
    function test_lastAdminCannotLeave() public {
        vm.startPrank(admin);
        vm.expectRevert(PromoSettler.CannotRemoveLastAdmin.selector);
        settler.removeAdmin(admin);
        vm.expectRevert(PromoSettler.CannotRemoveLastAdmin.selector);
        settler.renounceAdminRole();

        settler.addAdmin(newcomer);
        vm.expectEmit(address(settler));
        emit PromoSettler.RemovedAdmin(admin, admin);
        settler.renounceAdminRole();
        vm.stopPrank();

        assertEq(settler.admins(admin), 0);
        assertEq(settler.adminCount(), 1);
    }

    // ──────────────────────────────────────────────
    // SC-UFYJ: An admin transfer takes two steps
    // ──────────────────────────────────────────────

    // SC-UFYJ: An admin transfer takes two steps
    //
    // A two-step transfer stops a typo from handing the role to an address nobody controls.
    // Only the proposed address can accept, and accepting clears the proposal.
    function test_adminTransferTakesTwoSteps() public {
        vm.expectEmit(address(settler));
        emit PromoSettler.AdminTransferProposed(admin, newcomer);
        vm.prank(admin);
        settler.transferAdmin(newcomer);
        assertEq(settler.pendingAdmin(), newcomer);

        vm.prank(stranger);
        vm.expectRevert(PromoSettler.NotPendingAdmin.selector);
        settler.acceptAdmin();

        vm.expectEmit(address(settler));
        emit PromoSettler.NewAdmin(newcomer, newcomer);
        vm.prank(newcomer);
        settler.acceptAdmin();

        assertEq(settler.admins(newcomer), 1);
        assertEq(settler.adminCount(), 2);
        assertEq(settler.pendingAdmin(), address(0));
    }

    // SC-UFYJ: A transfer to the zero address or to an admin is refused
    function test_transferToZeroOrToAnAdminIsRefused() public {
        vm.startPrank(admin);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        settler.transferAdmin(address(0));

        settler.addAdmin(newcomer);
        vm.expectRevert(PromoSettler.AlreadyAdmin.selector);
        settler.transferAdmin(newcomer);
        vm.stopPrank();

        assertEq(settler.pendingAdmin(), address(0));
    }

    // SC-UFYJ: A proposed address that became an admin meanwhile cannot accept
    //
    // addAdmin can grant the role after transferAdmin proposed it. Accepting then would count
    // the same admin twice, so acceptAdmin reverts with AlreadyAdmin and adminCount stays at 2.
    function test_proposedAddressThatIsAlreadyAnAdminCannotAccept() public {
        vm.startPrank(admin);
        settler.transferAdmin(newcomer);
        settler.addAdmin(newcomer);
        vm.stopPrank();

        vm.prank(newcomer);
        vm.expectRevert(PromoSettler.AlreadyAdmin.selector);
        settler.acceptAdmin();
        assertEq(settler.adminCount(), 2);
    }

    // ──────────────────────────────────────────────
    // SC-UFYK: Removing or renouncing an admin withdraws its pending transfer
    // ──────────────────────────────────────────────

    // SC-UFYK: Removing a proposed address withdraws its transfer
    //
    // A removed address must not accept a transfer later. removeAdmin clears pendingAdmin even
    // when the address holds no role, and still emits RemovedAdmin.
    function test_removingAProposedAddressWithdrawsItsTransfer() public {
        vm.startPrank(admin);
        settler.transferAdmin(newcomer);
        vm.expectEmit(address(settler));
        emit PromoSettler.RemovedAdmin(newcomer, admin);
        settler.removeAdmin(newcomer);
        vm.stopPrank();
        assertEq(settler.pendingAdmin(), address(0));

        vm.prank(newcomer);
        vm.expectRevert(PromoSettler.NotPendingAdmin.selector);
        settler.acceptAdmin();
    }

    // SC-UFYK: Renouncing withdraws the renouncing admin's own pending transfer
    function test_renouncingWithdrawsTheRenouncingAdminsTransfer() public {
        vm.startPrank(admin);
        settler.transferAdmin(newcomer);
        settler.addAdmin(newcomer);
        vm.stopPrank();

        vm.prank(newcomer);
        settler.renounceAdminRole();

        assertEq(settler.admins(newcomer), 0);
        assertEq(settler.pendingAdmin(), address(0));
    }
}
