// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXS: Promo Credit Settlement
// UC-UFXV: Settle a Credited Trade
// FEAT-UFXT: Settler Administration
// UC-UFXW: Manage Settler Roles, UC-UFXX: Control Credit Settlement

import {Order, Side, SignatureType} from "exchange/libraries/OrderStructs.sol";

/// @dev The ProphetCTFExchange functions the settler calls. Declared inline: src/ imports no
///      implementation library, and the Order layout comes from the exchange's own struct file.
interface IProphetCTFExchange {
    function isOperator(address usr) external view returns (bool);
    function getCollateral() external view returns (address);
    function getCtf() external view returns (address);
    function matchOrders(
        Order memory takerOrder,
        Order[] memory makerOrders,
        uint256 takerFillAmount,
        uint256[] memory makerFillAmounts
    ) external;
}

/// @dev The one ERC-20 read the settler makes. Transfers go through the inline safe helpers.
interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

/// @dev The two Conditional Tokens (ERC-1155) calls the settler makes.
interface IConditionalTokensTransfer {
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;
}

/// @title PromoSettler
/// @notice Pays a promotional USDC credit to the Safe that signed the credited order and settles
///         the trade it funds in the same transaction, so the credit moves only when the trade
///         executes and one credit never pays more than its recorded total.
/// @dev The operator calls `settle` in place of `exchange.matchOrders` for a trade that spends a
///      credit. The settler holds the exchange operator role, pays the credit from the promo
///      wallet's allowance, forwards the match unchanged, and forwards every fee to the caller.
///      It holds no USDC and no outcome shares between calls.
contract PromoSettler {
    // ──────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────

    /// @dev One credit for one Safe and one promo code ID. The first settlement fixes `total`,
    ///      and `spent` never passes it. Both fit one storage slot.
    struct Credit {
        uint128 total;
        uint128 spent;
    }

    // ──────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────

    /// @notice The ProphetCTFExchange the settler forwards every match to.
    address public immutable exchange;

    /// @notice The EOA that funds every credit and receives every recovered token.
    address public immutable promoWallet;

    /// @notice The exchange's collateral, read from `exchange.getCollateral()` at deployment.
    address public immutable usdc;

    /// @notice The exchange's Conditional Tokens contract, read from `exchange.getCtf()`.
    address public immutable ctf;

    // ──────────────────────────────────────────────
    // Roles (the lp-vaults factory registry, ADR-UFZE)
    // ──────────────────────────────────────────────

    /// @dev 1 = active admin
    mapping(address => uint256) public admins;

    /// @dev 1 = active operator
    mapping(address => uint256) public operators;

    /// @dev Always >= 1. The last admin cannot leave.
    uint256 public adminCount;

    /// @dev Two-step admin transfer target
    address public pendingAdmin;

    // ──────────────────────────────────────────────
    // Controls and credit records
    // ──────────────────────────────────────────────

    /// @notice The ceiling on the credit total that a first settlement may record.
    uint128 public maxCreditUnits;

    /// @notice True while the admin stops settlement.
    bool public paused;

    /// @notice The credit record for each Safe and promo code ID.
    mapping(address safe => mapping(bytes32 codeId => Credit)) public credits;

    /// @dev 1 = not entered, 2 = entered. Starts at 1 so the first guarded call pays no
    ///      zero-to-nonzero write.
    uint256 private _reentrancyGuard = 1;

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error NotAdmin();
    error NotOperator();
    error NotPendingAdmin();
    error AlreadyAdmin();
    error CannotRemoveLastAdmin();
    error NotExchangeOperator();
    error NotConditionalTokens();
    error SettlerPaused();
    error Reentrancy();
    error ZeroAddress();
    error ZeroMaxCredit();
    error NothingToRecover();
    error TransferFailed();

    // SC-UFY4 to SC-UFY8: one error per refused credit
    error CreditedIndexOutOfRange();
    error CreditedOrderNotSafeBuy();
    error ZeroAmount();
    error AmountAboveFill();
    error CreditTotalAboveMaximum();
    error CreditTotalMismatch();
    error CreditExceeded();

    // ──────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────

    /// @notice One successful settlement: `amount` paid to `safe` for `codeId`, with the
    ///         record's running `spent` and its fixed `total` after the payment.
    event CreditSettled(
        address indexed safe,
        bytes32 indexed codeId,
        address indexed operator,
        uint256 amount,
        uint256 spent,
        uint256 total
    );

    event NewAdmin(address indexed newAdminAddress, address indexed admin);
    event NewOperator(address indexed newOperatorAddress, address indexed admin);
    event RemovedAdmin(address indexed removedAdmin, address indexed admin);
    event RemovedOperator(address indexed removedOperator, address indexed admin);
    event AdminTransferProposed(address indexed currentAdmin, address indexed proposedAdmin);
    event MaxCreditUnitsUpdated(uint128 oldValue, uint128 newValue);
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event Recovered(uint256 indexed tokenId, uint256 amount);

    // ──────────────────────────────────────────────
    // Modifiers
    // ──────────────────────────────────────────────

    modifier onlyAdmin() {
        if (admins[msg.sender] != 1) revert NotAdmin();
        _;
    }

    modifier onlyOperator() {
        if (operators[msg.sender] != 1) revert NotOperator();
        _;
    }

    /// @dev ADR-UFZB: the settler holds the exchange operator role, so it also requires the
    ///      caller to be an exchange operator. A settler operator the exchange admin never
    ///      approved cannot reach `matchOrders` through the settler.
    modifier onlyExchangeOperator() {
        if (!IProphetCTFExchange(exchange).isOperator(msg.sender)) revert NotExchangeOperator();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert SettlerPaused();
        _;
    }

    /// @dev Inside a receiver hook msg.sender is the token contract, so this pins the hooks to
    ///      the exchange's Conditional Tokens contract.
    modifier onlyConditionalTokens() {
        if (msg.sender != ctf) revert NotConditionalTokens();
        _;
    }

    /// @dev Inline reentrancy guard in the OpenZeppelin ReentrancyGuard shape.
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_reentrancyGuard != 1) revert Reentrancy();
        _reentrancyGuard = 2;
    }

    function _nonReentrantAfter() internal {
        _reentrancyGuard = 1;
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    // SC-UFYR, SC-UFYT: stores the fixed addresses and seeds one admin and one operator
    /// @param exchange_ ProphetCTFExchange; the settler reads USDC and Conditional Tokens from it
    /// @param promoWallet_ The funding source and the only recovery destination
    /// @param admin_ The first admin
    /// @param operator_ The first operator; the exchange must also list it to settle
    /// @param maxCreditUnits_ The first credit maximum, above 0
    constructor(address exchange_, address promoWallet_, address admin_, address operator_, uint128 maxCreditUnits_) {
        if (exchange_ == address(0) || promoWallet_ == address(0) || admin_ == address(0) || operator_ == address(0)) {
            revert ZeroAddress();
        }
        if (maxCreditUnits_ == 0) revert ZeroMaxCredit();

        exchange = exchange_;
        promoWallet = promoWallet_;
        // Reading both from the exchange removes two deploy values that could disagree with it.
        usdc = IProphetCTFExchange(exchange_).getCollateral();
        ctf = IProphetCTFExchange(exchange_).getCtf();

        admins[admin_] = 1;
        adminCount = 1;
        operators[operator_] = 1;
        maxCreditUnits = maxCreditUnits_;
    }

    // ──────────────────────────────────────────────
    // Role management (UC-UFXW), copied from the lp-vaults factory without the oracle
    // ──────────────────────────────────────────────

    // SC-UFYG: register an operator
    /// @notice Registers an address as a settler operator.
    /// @dev OPERATOR TRUST ASSUMPTION: An operator can call `settle`, which pays credits from the
    ///      promo wallet's allowance and forwards matches to the exchange. `settle` also requires
    ///      the exchange to list the operator, so this call alone grants no exchange power.
    /// @param operator_ Address to register
    function addOperator(address operator_) external onlyAdmin {
        operators[operator_] = 1;
        emit NewOperator(operator_, msg.sender);
    }

    // SC-UFYG: deregister an operator
    /// @notice Removes an address from the operator set.
    function removeOperator(address operator_) external onlyAdmin {
        operators[operator_] = 0;
        emit RemovedOperator(operator_, msg.sender);
    }

    // SC-UFYJ: first step of the two-step admin transfer
    /// @notice Proposes a new admin. The proposed address must call acceptAdmin() to complete.
    /// @param newAdmin Address to propose; must not be zero or already an admin
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        if (admins[newAdmin] == 1) revert AlreadyAdmin();

        pendingAdmin = newAdmin;
        emit AdminTransferProposed(msg.sender, newAdmin);
    }

    // SC-UFYJ: second step, the proposed admin claims the role
    /// @notice Completes the two-step admin transfer. Only callable by the pending admin.
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        // addAdmin can grant the role after transferAdmin proposed it. Accepting again would
        // count the same admin twice in adminCount.
        if (admins[msg.sender] == 1) revert AlreadyAdmin();

        admins[msg.sender] = 1;
        adminCount += 1;
        pendingAdmin = address(0);
        emit NewAdmin(msg.sender, msg.sender);
    }

    // SC-UFYH: one-step admin grant
    /// @notice Grants the admin role. A repeated add changes no state but still emits NewAdmin,
    ///         so adminCount never counts one address twice.
    function addAdmin(address admin_) external onlyAdmin {
        if (admin_ == address(0)) revert ZeroAddress();
        if (admins[admin_] != 1) {
            admins[admin_] = 1;
            adminCount++;
        }
        emit NewAdmin(admin_, msg.sender);
    }

    // SC-UFYH, SC-UFYI, SC-UFYK: revoke another admin
    /// @notice Revokes the admin role of an address. Removing an address that holds no role
    ///         changes no role state but still emits RemovedAdmin.
    /// @dev A pending proposal to the address is withdrawn in both cases, so a removed address
    ///      cannot accept an earlier transferAdmin (the lp-vaults departure from Auth).
    function removeAdmin(address admin) external onlyAdmin {
        if (admins[admin] == 1) {
            if (adminCount <= 1) revert CannotRemoveLastAdmin();
            admins[admin] = 0;
            adminCount--;
        }
        if (pendingAdmin == admin) pendingAdmin = address(0);
        emit RemovedAdmin(admin, msg.sender);
    }

    // SC-UFYI, SC-UFYK: the caller gives up its own admin role
    /// @notice Revokes the caller's admin role. Reverts if the caller is the last admin.
    function renounceAdminRole() external onlyAdmin {
        if (adminCount <= 1) revert CannotRemoveLastAdmin();
        admins[msg.sender] = 0;
        adminCount--;
        // A renounced address must not complete an earlier transferAdmin proposal.
        if (pendingAdmin == msg.sender) pendingAdmin = address(0);
        emit RemovedAdmin(msg.sender, msg.sender);
    }

    // ──────────────────────────────────────────────
    // Controls (UC-UFXX)
    // ──────────────────────────────────────────────

    // SC-UFYL: set the ceiling on new credit totals
    /// @notice Sets the credit maximum that a first settlement may record.
    /// @dev A record already created keeps its total (FR-UFZ4), so a lower maximum stops new
    ///      large credits without cutting one in progress.
    /// @param newMax The new maximum, above 0
    function setMaxCreditUnits(uint128 newMax) external onlyAdmin {
        if (newMax == 0) revert ZeroMaxCredit();
        emit MaxCreditUnitsUpdated(maxCreditUnits, newMax);
        maxCreditUnits = newMax;
    }

    // SC-UFYM, SC-UFYB: stop settlement without the promo wallet key
    /// @notice Stops every settlement until unpause.
    function pause() external onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    // SC-UFYM, SC-UFYB: restart settlement
    /// @notice Lets settlement run again.
    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    // SC-UFYN, SC-UFYO, SC-UFYP: return a stray token to the promo wallet
    /// @notice Sends the settler's whole balance of one token to the promo wallet: USDC for
    ///         `tokenId = 0`, the outcome token `tokenId` otherwise.
    /// @dev The settler holds nothing at rest, so only a donation reaches it. The destination is
    ///      the immutable promo wallet, so a compromised admin key cannot take the token
    ///      (ADR-UFZF). A zero balance reverts, so every Recovered event names a real transfer.
    /// @param tokenId 0 for USDC, or a Conditional Tokens position ID
    function recover(uint256 tokenId) external onlyAdmin nonReentrant {
        uint256 amount = tokenId == 0
            ? IERC20Balance(usdc).balanceOf(address(this))
            : IConditionalTokensTransfer(ctf).balanceOf(address(this), tokenId);
        if (amount == 0) revert NothingToRecover();
        emit Recovered(tokenId, amount);

        if (tokenId == 0) {
            _safeTransfer(usdc, promoWallet, amount);
        } else {
            IConditionalTokensTransfer(ctf).safeTransferFrom(address(this), promoWallet, tokenId, amount, "");
        }
    }

    // ──────────────────────────────────────────────
    // Settlement (UC-UFXV)
    // ──────────────────────────────────────────────

    // SC-UFY0 to SC-UFYD: pay the credit, forward the match, forward the fees
    /// @notice Pays `amount` USDC from the promo wallet to the maker of the credited order, then
    ///         settles the match on the exchange and forwards every fee to the caller.
    /// @dev Checks, then effects, then interactions. The record update and the event come before
    ///      the three external calls, and a revert anywhere undoes the payment with the trade.
    ///
    ///      OPERATOR TRUST ASSUMPTION: The operator chooses the promo code ID, the credit total
    ///      up to the admin maximum, the amount up to the credited order's fill, and which signed
    ///      orders to match. The last power is the exchange operator's own power, and the settler
    ///      grants it only to a caller the exchange already lists as an operator. The recipient
    ///      is always the maker of a signed Safe BUY, so the operator cannot choose where a
    ///      credit goes. A compromised operator key can sign orders from Safes it controls under
    ///      fresh code IDs, so the promo wallet's allowance bounds the worst-case loss.
    ///
    ///      MEV analysis: Every order is signed, and the exchange enforces each signed price.
    ///      The settler adds no price, and its credit record depends only on its own storage,
    ///      so ordering other transactions around a settlement moves no value to the one who
    ///      orders them.
    /// @param codeId The promo code ID: bytes32(uint256(uint128(referral_codes.id)))
    /// @param creditTotal The full credit; fixed by the first settlement for this Safe and code
    /// @param amount The USDC this settlement pays, at least 1 and at most the credited fill
    /// @param creditedIndex 0 names the taker order, i + 1 names makerOrders[i]
    function settle(
        bytes32 codeId,
        uint128 creditTotal,
        uint128 amount,
        uint256 creditedIndex,
        Order calldata takerOrder,
        Order[] calldata makerOrders,
        uint256 takerFillAmount,
        uint256[] calldata makerFillAmounts
    ) external onlyOperator onlyExchangeOperator whenNotPaused nonReentrant {
        (address safe, uint256 fill) = _creditedOrder(
            creditedIndex, takerOrder, makerOrders, takerFillAmount, makerFillAmounts
        );
        // The exchange pulls exactly the fill from the Safe. A larger credit would leave promo
        // USDC in the Safe, free to withdraw without trading.
        if (amount == 0) revert ZeroAmount();
        if (amount > fill) revert AmountAboveFill();

        (uint128 spent, uint128 total) = _recordCredit(safe, codeId, creditTotal, amount);
        emit CreditSettled(safe, codeId, msg.sender, amount, spent, total);

        _safeTransferFrom(usdc, promoWallet, safe, amount);
        IProphetCTFExchange(exchange).matchOrders(takerOrder, makerOrders, takerFillAmount, makerFillAmounts);
        _forwardFees(takerOrder, makerOrders);
    }

    // SC-UFY2, SC-UFY8: select the credited order and require a Safe BUY
    /// @dev Returns the credited order's maker and its fill in maker amount, which for a BUY is
    ///      the USDC the exchange pulls from the maker. POLY_GNOSIS_SAFE makes the exchange check
    ///      that the maker is the Safe the signer owns, so the recipient is never an address the
    ///      caller chose (FR-UFYX).
    function _creditedOrder(
        uint256 creditedIndex,
        Order calldata takerOrder,
        Order[] calldata makerOrders,
        uint256 takerFillAmount,
        uint256[] calldata makerFillAmounts
    ) internal pure returns (address maker, uint256 fill) {
        Order calldata credited = takerOrder;
        fill = takerFillAmount;
        if (creditedIndex != 0) {
            if (creditedIndex > makerOrders.length) revert CreditedIndexOutOfRange();
            credited = makerOrders[creditedIndex - 1];
            fill = makerFillAmounts[creditedIndex - 1];
        }
        if (credited.side != Side.BUY || credited.signatureType != SignatureType.POLY_GNOSIS_SAFE) {
            revert CreditedOrderNotSafeBuy();
        }
        maker = credited.maker;
    }

    // SC-UFY3 to SC-UFY6: fix the total on the first settlement and cap spent at it
    /// @dev A new record takes `creditTotal`, bounded by the maximum at that moment. A later
    ///      settlement must pass the same total. A zero total needs no own check: `amount` is at
    ///      least 1, so the cap below reverts with CreditExceeded and the revert discards the
    ///      stored zero. The sum is compared in 256 bits so a large amount cannot overflow the
    ///      128-bit field before the cap rejects it.
    function _recordCredit(address safe, bytes32 codeId, uint128 creditTotal, uint128 amount)
        internal
        returns (uint128 spent, uint128 total)
    {
        Credit storage credit = credits[safe][codeId];
        total = credit.total;
        if (total == 0) {
            if (creditTotal > maxCreditUnits) revert CreditTotalAboveMaximum();
            total = creditTotal;
            credit.total = creditTotal;
        } else if (creditTotal != total) {
            revert CreditTotalMismatch();
        }
        if (uint256(credit.spent) + amount > total) revert CreditExceeded();
        spent = credit.spent + amount;
        credit.spent = spent;
    }

    // SC-UFYC: forward every fee the exchange paid the settler
    /// @dev The exchange pays fees to its msg.sender, the settler: a BUY taker's fee in the bought
    ///      token, a SELL maker's fee in USDC, and a mint maker's fee in that maker order's own
    ///      token. The refund and the delta surplus go to the taker order's maker, so after the
    ///      match the settler holds only fees. Sending the whole balance of USDC and of every
    ///      order's token ID leaves the settler empty (FR-UFYZ). A repeated token ID finds a zero
    ///      balance on its second visit and moves nothing.
    function _forwardFees(Order calldata takerOrder, Order[] calldata makerOrders) internal {
        uint256 usdcBalance = IERC20Balance(usdc).balanceOf(address(this));
        if (usdcBalance > 0) _safeTransfer(usdc, msg.sender, usdcBalance);

        _forwardShares(takerOrder.tokenId);
        uint256 length = makerOrders.length;
        for (uint256 i; i < length; ++i) {
            _forwardShares(makerOrders[i].tokenId);
        }
    }

    /// @dev Sends the settler's whole balance of `tokenId` to the caller, if it holds any.
    function _forwardShares(uint256 tokenId) internal {
        uint256 balance = IConditionalTokensTransfer(ctf).balanceOf(address(this), tokenId);
        if (balance > 0) {
            IConditionalTokensTransfer(ctf).safeTransferFrom(address(this), msg.sender, tokenId, balance, "");
        }
    }

    // ──────────────────────────────────────────────
    // ERC-1155 receiver (SC-UFYE)
    // ──────────────────────────────────────────────

    /// @notice Accepts a single outcome-token transfer from the Conditional Tokens contract only.
    /// @dev The exchange sends share fees with safeTransferFrom, which calls this hook on a
    ///      contract. Without it every credited BUY reverts. The hook changes no state.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        view
        onlyConditionalTokens
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /// @notice Accepts a batch outcome-token transfer from the Conditional Tokens contract only.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        onlyConditionalTokens
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice ERC-165: true for IERC1155Receiver (0x4e2312e0) and IERC165 (0x01ffc9a7).
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x4e2312e0 || interfaceId == 0x01ffc9a7;
    }

    // ──────────────────────────────────────────────
    // Internal: token transfers (inlined per pattern policy)
    // ──────────────────────────────────────────────

    /// @dev Pull-direction ERC-20 transfer. Handles both bool-returning and non-bool-returning
    ///      tokens (USDT semantics).
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    /// @dev Push-direction ERC-20 transfer with the same return handling.
    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
