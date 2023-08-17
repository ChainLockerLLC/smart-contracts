//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 **/

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\
/////////// o=o=o=o=o TokenLocker o=o=o=o=o \\\\\\\\\\\
// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/// @notice interface for ERC-20 standard token contract, including EIP2612 permit function
interface IERC20Permit {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice interface to Receipt.sol, which returns USD-value receipts for a provided token amount
interface IReceipt {
    function printReceipt(
        address token,
        uint256 tokenAmount,
        uint256 decimals
    ) external returns (uint256, uint256);
}

/// @notice used for valueCondition checks - user must ensure the correct dAPI/data feed proxy address is provided to the constructor
/// @dev See docs.api3.org for comments about usage
interface IProxy {
    function read() external view returns (int224 value, uint32 timestamp);
}

/// @notice Solbase / Solady's SafeTransferLib 'SafeTransfer()' and 'SafeTransferFrom()'.  Extracted from library and pasted for convenience, transparency, and size minimization.
/// @author Solbase / Solady (https://github.com/Sol-DAO/solbase/blob/main/src/utils/SafeTransferLib.sol / https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// Licenses copied below
/// @dev implemented as abstract contract rather than library for size/gas reasons
abstract contract SafeTransferLib {
    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();

    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    function safeTransfer(address token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0x00, 0xa9059cbb)
            mstore(0x20, to) // Append the "to" argument.
            mstore(0x40, amount) // Append the "amount" argument.

            if iszero(
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(eq(mload(0x00), 1), iszero(returndatasize())),
                    // We use 0x44 because that's the total length of our calldata (0x04 + 0x20 * 2)
                    // Counterintuitively, this call() must be positioned after the or() in the
                    // surrounding and() because and() evaluates its arguments from right to left.
                    call(gas(), token, 0, 0x1c, 0x44, 0x00, 0x20)
                )
            ) {
                // Store the function selector of `TransferFailed()`.
                mstore(0x00, 0x90b8ec18)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            mstore(0x40, memPointer) // Restore the memPointer.
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0x00, 0x23b872dd)
            mstore(0x20, from) // Append the "from" argument.
            mstore(0x40, to) // Append the "to" argument.
            mstore(0x60, amount) // Append the "amount" argument.

            if iszero(
                and(
                    // Set success to whether the call reverted, if not we check it either
                    // returned exactly 1 (can't just be non-zero data), or had no return data.
                    or(eq(mload(0x00), 1), iszero(returndatasize())),
                    // We use 0x64 because that's the total length of our calldata (0x04 + 0x20 * 3)
                    // Counterintuitively, this call() must be positioned after the or() in the
                    // surrounding and() because and() evaluates its arguments from right to left.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                // Store the function selector of `TransferFromFailed()`.
                mstore(0x00, 0x7939f424)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }
    }
}

/// @notice Gas-optimized reentrancy protection for smart contracts.
/// @author Solbase (https://github.com/Sol-DAO/solbase/blob/main/src/utils/ReentrancyGuard.sol)
/// License copied below
/// @dev sole difference from Solmate's ReentrancyGuard is 'Reentrancy()' custom error
abstract contract ReentrancyGuard {
    uint256 private locked = 1;
    error Reentrancy();

    modifier nonReentrant() virtual {
        if (locked == 2) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }
}

/**
 * @title       o=o=o=o=o TokenLocker o=o=o=o=o
 **/
/**
 * @author      o=o=o=o=o ChainLocker LLC o=o=o=o=o
 **/
/** @notice non-custodial smart escrow contract using ERC20 tokens on Ethereum Mainnet, supporting:
 * partial or full deposit amount
 * refundable or non-refundable deposit upon expiry
 * deposit via transfer or EIP2612 permit signature
 * seller-identified buyer or open offer
 * escrow expiration denominated in seconds
 * optional value condition for execution (contingent execution based on oracle-fed external data value)
 * buyer and seller addresses replaceable by applicable party
 **/
/** @dev executes and releases 'totalAmount' to 'seller' iff:
 * (1) 'buyer' and 'seller' have both called 'readyToExecute()'
 * (2) balanceOf(address(this)) >= 'totalAmount'
 * (3) 'expirationTime' > block.timestamp
 * (4) if there is a valueCondition, such condition is satisfied
 *
 * otherwise, amount held in address(this) will be treated according to the code in 'checkIfExpired()' when called following expiry
 *
 * variables are public for interface friendliness and enabling getters.
 * 'seller', 'buyer', 'deposit', 'refundable', 'openOffer' and other terminology, naming, and descriptors herein are used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe nor imply any agreement or relationship between or among any author, modifier, deployer, user, contract, asset, or other relevant participant hereto
 **/
contract TokenLocker is ReentrancyGuard, SafeTransferLib {
    /** @notice enum values represent the following:
     *** 0 ('None'): no value contingency to ChainLocker execution; '_maximumValue', '_minimumValue' and '_dataFeedProxyAddress' params are ignored.
     *** 1 ('LessThanOrEqual'): the value returned from '_dataFeedProxyAddress' must be <= '_maximumValue' when calling 'execute()'; '_minimumValue' param is ignored
     *** 2 ('GreaterThanOrEqual'): the value returned from '_dataFeedProxyAddress' must be >= '_minimumValue' when calling 'execute()'; '_maximumValue' param is ignored
     *** 3 ('Both'): the value returned from '_dataFeedProxyAddress' must be both <= '_maximumValue' and >= '_minimumValue' when calling 'execute()'
     */
    enum ValueCondition {
        None,
        LessThanOrEqual,
        GreaterThanOrEqual,
        Both
    }

    // Receipt.sol contract address, ETH mainnet (CURRENTLY PLACEHOLDER)
    // constant rather than immutable to ease stack in constructor
    IReceipt internal constant RECEIPT = IReceipt(address(1234));

    // 60 seconds * 60 minutes * 24 hours
    uint256 internal constant ONE_DAY = 86400;

    // internal visibility for gas savings, as 'tokenContract' is public and bears the same contract address
    IERC20Permit internal immutable erc20;

    IProxy internal immutable dataFeedProxy;
    ValueCondition public immutable valueCondition;
    address public immutable tokenContract;
    bool public immutable openOffer;
    bool public immutable refundable;
    int224 public immutable maximumValue;
    int224 public immutable minimumValue;
    uint256 public immutable deposit;
    uint256 public immutable totalAmount;
    uint256 public immutable expirationTime;

    address public buyer;
    address public seller;
    bool public deposited;
    bool public isExpired;
    bool public buyerApproved;
    bool public sellerApproved;

    mapping(address => uint256) public amountDeposited;
    mapping(address => uint256) public amountWithdrawable;

    ///
    /// EVENTS
    ///

    event TokenLocker_AmountReceived(uint256 tokenAmount);
    event TokenLocker_BuyerReady();
    event TokenLocker_BuyerUpdated(address newBuyer);
    event TokenLocker_DepositedAmountTransferred(
        address receiver,
        uint256 amount
    );
    event TokenLocker_DepositInEscrow(address depositor);
    event TokenLocker_Deployed(
        bool refundable,
        bool openOffer,
        uint256 deposit,
        uint256 totalAmount,
        uint256 expirationTime,
        address seller,
        address buyer,
        address tokenContract
    );
    event TokenLocker_DeployedCondition(
        address dataFeedProxy,
        ValueCondition valueCondition,
        int224 minimumValue,
        int224 maximumValue
    );
    // emit effective time of execution for ease of log collection, plus valueCondition value & value-reading oracle proxy contract (if applicable)
    event TokenLocker_Executed(
        uint256 indexed effectiveTime,
        int224 valueCondition,
        address dataFeedProxy
    );
    event TokenLocker_Expired();
    event TokenLocker_TotalAmountInEscrow();
    event TokenLocker_SellerReady();
    event TokenLocker_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error TokenLocker_AmountNotApprovedForTransferFrom();
    error TokenLocker_BalanceExceedsTotalAmount();
    error TokenLocker_DepositGreaterThanTotalAmount();
    error TokenLocker_IsExpired();
    error TokenLocker_MustDepositTotalAmount();
    error TokenLocker_NotBuyer();
    error TokenLocker_NotSeller();
    error TokenLocker_NonERC20Contract();
    error TokenLocker_NotReadyToExecute();
    error TokenLocker_OnlyOpenOffer();
    error TokenLocker_ValueConditionConflict();
    error TokenLocker_ValueOlderThanOneDay();
    error TokenLocker_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the TokenLocker smart escrow contract. Arranger MUST verify that _tokenContract is both ERC20- and EIP2612- standard compliant and that the _dataFeedProxyAddress is accurate (if '_valueCondition' != 0), as neither address(this) nor the ChainLockerFactory.sol contract fully perform such checks.
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer: whether this escrow is open to any prospective 'buyer' (revocable at seller's option). A 'buyer' assents by sending 'deposit' to address(this) after deployment
    /** @param _valueCondition: uint8 corresponding to the ValueCondition enum (passed as 0, 1, 2, or 3), which is the value contingency (via oracle) which must be satisfied for the ChainLocker to release. Options are 0, 1, 2, or 3, which
     *** respectively correspond to: none, <=, >=, or two conditions (both <= and >=, for the '_maximumValue' and '_minimumValue' params, respectively).
     *** For an **EXACT** value condition (i.e. that the returned value must equal an exact number), pass '3' (Both) and pass such exact required value as both '_minimumValue' and '_maximumValue'
     *** Passed as uint8 rather than enum for easier composability */
    /// @param _maximumValue: the maximum permitted int224 value returned from the applicable dAPI / API3 data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 2.
    /// @param _minimumValue: the minimum permitted int224 value returned from the applicable dAPI / API3 data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 1.
    /// @param _deposit: deposit amount, which must be <= '_totalAmount' (< for partial deposit, == for full deposit). If 'openOffer', msg.sender must deposit entire 'totalAmount', but if '_refundable', this amount will be refundable to the accepting address of the open offer (buyer) at expiry if not yet executed
    /// @param _totalAmount: total amount which will be deposited in this contract, ultimately intended for '_seller'
    /// @param _expirationTime: _expirationTime in seconds (Unix time), which will be compared against block.timestamp. input type(uint256).max for no expiry (not recommended, as funds will only be released upon execution or if seller rejects depositor -- refunds only process at expiry)
    /// @param _seller: the seller's address, recipient of the '_totalAmount' if the contract executes
    /// @param _buyer: the buyer's address, who will cause the '_totalAmount' to be paid to this address. Ignored if 'openOffer'
    /// @param _tokenContract: contract address for the ERC20 token used in this TokenLocker
    /// @param _dataFeedProxyAddress: contract address for the proxy that will be used to access the applicable dAPI / data feed for the '_valueCondition' query. Ignored if '_valueCondition' == 0. Person calling this method should ensure the applicable sponsor wallet is sufficiently funded for their intended purposes, if applicable.
    constructor(
        bool _refundable,
        bool _openOffer,
        uint8 _valueCondition,
        int224 _maximumValue,
        int224 _minimumValue,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address _seller,
        address _buyer,
        address _tokenContract,
        address _dataFeedProxyAddress
    ) payable {
        if (_deposit > _totalAmount)
            revert TokenLocker_DepositGreaterThanTotalAmount();
        if (_totalAmount == 0) revert TokenLocker_ZeroAmount();
        if (_expirationTime <= block.timestamp) revert TokenLocker_IsExpired();
        // '_valueCondition' cannot be > 3, nor can '_maximumValue' be < '_minimumValue' if _valueCondition == 3 (ValueCondition.Both)
        if (
            _valueCondition > 3 ||
            (_valueCondition == 3 && _maximumValue < _minimumValue)
        ) revert TokenLocker_ValueConditionConflict();

        // quick staticcall condition check that '_tokenContract' is at least partially ERC-20 compliant by checking if both totalSupply and balanceOf functions exist
        (bool successTotalSupply, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("totalSupply()")
        );

        (bool successBalanceOf, ) = _tokenContract.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        if (!successTotalSupply || !successBalanceOf)
            revert TokenLocker_NonERC20Contract();

        refundable = _refundable;
        openOffer = _openOffer;
        valueCondition = ValueCondition(_valueCondition);
        maximumValue = _maximumValue;
        minimumValue = _minimumValue;
        deposit = _deposit;
        totalAmount = _totalAmount;
        seller = _seller;
        buyer = _buyer;
        tokenContract = _tokenContract;
        expirationTime = _expirationTime;
        erc20 = IERC20Permit(_tokenContract);
        dataFeedProxy = IProxy(_dataFeedProxyAddress);

        emit TokenLocker_Deployed(
            _refundable,
            _openOffer,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer,
            _tokenContract
        );
        // if execution is contingent upon a value or values, emit relevant information
        if (_valueCondition != 0)
            emit TokenLocker_DeployedCondition(
                _dataFeedProxyAddress,
                valueCondition,
                _minimumValue,
                _maximumValue
            );
    }

    /// @notice deposit value to 'address(this)' by permitting address(this) to safeTransferFrom '_amount' of tokens from '_depositor'
    /** @dev max '_amount limit of 'totalAmount', and if 'totalAmount' is already held or escrow has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited', and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    /// @param _depositor: depositor of the '_amount' of tokens, often msg.sender/originating EOA, but must == 'buyer' if this is not an open offer (!openOffer)
    /// @param _amount: amount of tokens deposited. If 'openOffer', '_amount' must == 'totalAmount'
    /// @param _deadline: deadline for usage of the permit approval signature
    /// @param v: ECDSA sig parameter
    /// @param r: ECDSA sig parameter
    /// @param s: ECDSA sig parameter
    function depositTokensWithPermit(
        address _depositor,
        uint256 _amount,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        uint256 _balance = erc20.balanceOf(address(this)) + _amount;
        if (_balance > totalAmount)
            revert TokenLocker_BalanceExceedsTotalAmount();
        if (!openOffer && _depositor != buyer) revert TokenLocker_NotBuyer();
        if (_deadline < block.timestamp || expirationTime <= block.timestamp)
            revert TokenLocker_IsExpired();
        if (openOffer && _balance < totalAmount)
            revert TokenLocker_MustDepositTotalAmount();

        if (_balance >= deposit && !deposited) {
            // if this TokenLocker is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = _depositor;
                emit TokenLocker_BuyerUpdated(_depositor);
            }
            deposited = true;
            emit TokenLocker_DepositInEscrow(_depositor);
        }
        if (_balance == totalAmount) emit TokenLocker_TotalAmountInEscrow();

        emit TokenLocker_AmountReceived(_amount);
        amountDeposited[_depositor] += _amount;
        erc20.permit(_depositor, address(this), _amount, _deadline, v, r, s);
        safeTransferFrom(tokenContract, _depositor, address(this), _amount);
    }

    /// @notice deposit value to 'address(this)' via safeTransferFrom '_amount' of tokens from msg.sender; provided msg.sender has approved address(this) to transferFrom such 'amount'
    /** @dev msg.sender must have erc20.approve(address(this), _amount) prior to calling this function
     ** max '_amount limit of 'totalAmount', and if 'totalAmount' is already held or this TokenLocker has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited', and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    /// @param _amount: amount of tokens deposited. If 'openOffer', '_amount' must == 'totalAmount'
    function depositTokens(uint256 _amount) external nonReentrant {
        uint256 _balance = erc20.balanceOf(address(this)) + _amount;
        if (_balance > totalAmount)
            revert TokenLocker_BalanceExceedsTotalAmount();
        if (!openOffer && msg.sender != buyer) revert TokenLocker_NotBuyer();
        if (erc20.allowance(msg.sender, address(this)) < _amount)
            revert TokenLocker_AmountNotApprovedForTransferFrom();
        if (expirationTime <= block.timestamp) revert TokenLocker_IsExpired();
        if (openOffer && _balance < totalAmount)
            revert TokenLocker_MustDepositTotalAmount();

        if (_balance >= deposit && !deposited) {
            // if this TokenLocker is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = msg.sender;
                emit TokenLocker_BuyerUpdated(msg.sender);
            }
            deposited = true;
            emit TokenLocker_DepositInEscrow(msg.sender);
        }
        if (_balance == totalAmount) emit TokenLocker_TotalAmountInEscrow();

        emit TokenLocker_AmountReceived(_amount);
        amountDeposited[msg.sender] += _amount;
        safeTransferFrom(tokenContract, msg.sender, address(this), _amount);
    }

    /// @notice for the current seller to designate a new recipient address
    /// @param _seller: new recipient address of seller
    function updateSeller(address _seller) external {
        if (msg.sender != seller) revert TokenLocker_NotSeller();

        if (!checkIfExpired()) {
            seller = _seller;
            emit TokenLocker_SellerUpdated(_seller);
        }
    }

    /// @notice for the current 'buyer' to designate a new buyer address
    /// @param _buyer: new address of buyer
    function updateBuyer(address _buyer) external {
        if (msg.sender != buyer) revert TokenLocker_NotBuyer();

        // transfer 'amountDeposited[buyer]' to the new '_buyer', delete the existing buyer's 'amountDeposited', and update the 'buyer' state variable
        if (!checkIfExpired()) {
            amountDeposited[_buyer] = amountDeposited[buyer];
            delete amountDeposited[buyer];

            buyer = _buyer;
            emit TokenLocker_BuyerUpdated(_buyer);
        }
    }

    /// @notice seller and buyer each call this when ready to execute; other address callers will have no effect
    /** @dev no need for an erc20.balanceOf(address(this)) check because (1) a reasonable seller will only pass 'true'
     *** if 'totalAmount' is in place, and (2) 'execute()' requires erc20.balanceOf(address(this)) >= 'totalAmount';
     *** separate conditionals in case 'buyer' == 'seller' */
    function readyToExecute() external {
        if (msg.sender == seller) {
            sellerApproved = true;
            emit TokenLocker_SellerReady();
        }
        if (msg.sender == buyer) {
            buyerApproved = true;
            emit TokenLocker_BuyerReady();
        }
    }

    /** @notice checks if both buyer and seller are ready to execute, and that any applicable 'ValueCondition' is met, and expiration has not been met;
     *** if so, this contract executes and pays seller; if not, totalAmount deposit returned to buyer (if refundable); callable by any external address **/
    /** @dev requires entire 'totalAmount' be held by address(this). If properly executes, pays seller and emits event with effective time of execution.
     *** Does not require amountDeposited[buyer] == erc20.balanceOf(address(this)) to allow buyer to deposit from multiple addresses if desired; */
    function execute() external {
        if (
            !sellerApproved ||
            !buyerApproved ||
            erc20.balanceOf(address(this)) < totalAmount
        ) revert TokenLocker_NotReadyToExecute();

        // delete approvals
        delete sellerApproved;
        delete buyerApproved;

        int224 _value;
        // only perform these checks if ChainLocker execution is contingent upon specified external value condition(s)
        if (valueCondition != ValueCondition.None) {
            (int224 _returnedValue, uint32 _timestamp) = dataFeedProxy.read();
            // require a value update within the last day
            if (block.timestamp - _timestamp > ONE_DAY)
                revert TokenLocker_ValueOlderThanOneDay();

            if (
                (valueCondition == ValueCondition.LessThanOrEqual &&
                    _returnedValue > maximumValue) ||
                (valueCondition == ValueCondition.GreaterThanOrEqual &&
                    _returnedValue < minimumValue) ||
                (valueCondition == ValueCondition.Both &&
                    (_returnedValue > maximumValue ||
                        _returnedValue < minimumValue))
            ) revert TokenLocker_ValueConditionConflict();
            // if no reversion, store the '_returnedValue' and proceed with execution
            else _value = _returnedValue;
        }

        if (!checkIfExpired()) {
            delete deposited;
            delete amountDeposited[buyer];

            // safeTransfer 'totalAmount' to 'seller'; note the deposit functions perform checks against depositing more than the 'totalAmount',
            // and further safeguarded by any excess balance being returned to buyer after expiry in 'checkIfExpired()'
            safeTransfer(tokenContract, seller, totalAmount);

            // effective time of execution is block.timestamp upon payment to seller
            emit TokenLocker_Executed(
                block.timestamp,
                _value,
                address(dataFeedProxy)
            );
            emit TokenLocker_DepositedAmountTransferred(seller, totalAmount);
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for 'tokenContract', for example for 'seller' to submit 'totalAmount' immediately after execution/release of TokenLocker
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing '_paymentId' and '_usdValue' emitted by Receipt.sol
    /// @param _tokenAmount: amount of tokens (corresponding to this TokenLocker's 'tokenContract') for which caller is seeking the total USD value receipt
    function getReceipt(
        uint256 _tokenAmount
    ) external returns (uint256 _paymentId, uint256 _usdValue) {
        return
            RECEIPT.printReceipt(tokenContract, _tokenAmount, erc20.decimals());
    }

    /// @notice for a 'seller' to reject any depositing address (including 'buyer') and cause the return of their deposited amount
    /// @param _depositor: address being rejected by 'seller' which will subsequently be able to withdraw their 'amountDeposited'
    /// @dev if !openOffer and 'seller' passes 'buyer' to this function, 'buyer' will need to call 'updateBuyer' to choose another address and re-deposit tokens.
    function rejectDepositor(address _depositor) external nonReentrant {
        if (msg.sender != seller) revert TokenLocker_NotSeller();

        uint256 _amtDeposited = amountDeposited[_depositor];
        if (_amtDeposited == 0) revert TokenLocker_ZeroAmount();

        delete amountDeposited[_depositor];
        // regardless of whether '_depositor' is 'buyer', permit them to withdraw their 'amountWithdrawable' balance
        amountWithdrawable[_depositor] = _amtDeposited;

        // reset 'deposited' and 'buyerApproved' variables if 'seller' passed 'buyer' as '_depositor'
        if (_depositor == buyer) {
            delete deposited;
            delete buyerApproved;
            // if 'openOffer', delete the 'buyer' variable so the next valid depositor will become 'buyer'
            // we do not delete 'buyer' if !openOffer, to allow the 'buyer' to choose another address via 'updateBuyer', rather than irreversibly deleting the variable
            if (openOffer) {
                delete buyer;
                emit TokenLocker_BuyerUpdated(address(0));
            }
        }
    }

    /// @notice allows an address to withdraw 'amountWithdrawable' of tokens, such as a refundable amount post-expiry or if seller has called 'rejectDepositor' for such an address, etc.
    /// @dev used by a depositing address which 'seller' passed to 'rejectDepositor()', or if 'isExpired', used by 'buyer' and/or 'seller' (as applicable)
    function withdraw() external {
        uint256 _amt = amountWithdrawable[msg.sender];
        if (_amt == 0) revert TokenLocker_ZeroAmount();

        delete amountWithdrawable[msg.sender];
        safeTransfer(tokenContract, msg.sender, _amt);
        emit TokenLocker_DepositedAmountTransferred(msg.sender, _amt);
    }

    /// @notice check if expired, and if so, handle refundability by updating the 'amountWithdrawable' mapping as applicable
    /** @dev if expired, update isExpired boolean. If non-refundable, update seller's 'amountWithdrawable' to be the non-refundable deposit amount before updating buyer's mapping for the remainder.
     *** If refundable, update buyer's 'amountWithdrawable' to the entire balance. */
    /// @return isExpired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp) {
            isExpired = true;
            uint256 _balance = erc20.balanceOf(address(this));
            bool _isDeposited = deposited;

            emit TokenLocker_Expired();

            delete deposited;
            delete amountDeposited[buyer];
            if (_balance > 0) {
                // if non-refundable deposit and 'deposit' hasn't been reset to 'false' by a successful 'execute()', enable 'seller' to withdraw the 'deposit' amount before enabling the remainder amount (if any) to be withdrawn by buyer
                if (!refundable && _isDeposited) {
                    amountWithdrawable[seller] = deposit;
                    amountWithdrawable[buyer] = _balance - deposit;
                } else amountWithdrawable[buyer] = _balance;
            }
        }
        return isExpired;
    }
}

/** 
Sol-DAO License:
MIT License

Copyright (c) 2022 SolDAO.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

**********************************

Solady License:
MIT License

Copyright (c) 2022 Solady.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
 */
