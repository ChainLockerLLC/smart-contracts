//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 **/

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\
//////////// o=o=o=o=o EthLocker o=o=o=o=o \\\\\\\\\\\\
// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/// @notice interface to Receipt.sol, which optionally returns USD-value receipts for a provided token amount
interface IReceipt {
    function printReceipt(
        address token,
        uint256 tokenAmount
    ) external returns (uint256, uint256);
}

/// @notice used for valueCondition checks - user must ensure the correct dAPI/data feed proxy address is provided to the constructor
/// @dev See docs.api3.org for comments about usage
interface IProxy {
    function read() external view returns (int224 value, uint32 timestamp);
}

/// @notice Solbase / Solady's SafeTransferLib 'SafeTransferETH()'.  Extracted from library and pasted for convenience, transparency, and size minimization.
/// @author Solbase / Solady (https://github.com/Sol-DAO/solbase/blob/main/src/utils/SafeTransferLib.sol / https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// Licenses copied below
/// @dev implemented as abstract contract rather than library for size/gas reasons
abstract contract SafeTransferLib {
    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /// @dev Sends `amount` (in wei) ETH to `to`.
    /// Reverts upon failure.
    function safeTransferETH(address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the ETH and check if it succeeded or not.
            if iszero(call(gas(), to, amount, 0, 0, 0, 0)) {
                // Store the function selector of `ETHTransferFailed()`.
                mstore(0x00, 0xb12d13eb)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }
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
 * @title       o=o=o=o=o EthLocker o=o=o=o=o
 **/
/**
 * @author      o=o=o=o=o ChainLocker LLC o=o=o=o=o
 **/
/** @notice non-custodial smart escrow contract for ETH-denominated transaction on Ethereum Mainnet, supporting:
 * partial or full deposit amount
 * refundable or non-refundable deposit upon expiry
 * seller-identified buyer or open offer
 * escrow expiration denominated in seconds
 * optional value condition for execution (contingent execution based on oracle-fed external data value)
 * buyer and seller addresses replaceable by applicable party
 **/
/** @dev executes and releases 'totalAmount' to 'seller' iff:
 * (1) 'buyer' and 'seller' have both called 'readyToExecute()'
 * (2) address(this).balance >= 'totalAmount'
 * (3) 'expirationTime' > block.timestamp
 * (4) if there is a valueCondition, such condition is satisfied
 *
 * otherwise, amount held in address(this) will be treated according to the code in 'checkIfExpired()' when called following expiry
 *
 * variables are public for interface friendliness and enabling getters.
 * 'seller', 'buyer', 'deposit', 'refundable', 'open offer' and other terminology, naming, and descriptors herein are used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe nor imply any agreement or relationship between or among any author, modifier, deployer, user, contract, asset, or other relevant participant hereto
 **/
contract EthLocker is ReentrancyGuard, SafeTransferLib {
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

    IProxy public immutable dataFeedProxy;
    ValueCondition public immutable valueCondition;
    bool public immutable openOffer;
    bool public immutable refundable;
    int224 public immutable maximumValue;
    int224 public immutable minimumValue;
    uint256 public immutable deposit;
    uint256 public immutable expirationTime;
    uint256 public immutable totalAmount;

    bool public deposited;
    bool public isExpired;
    bool public buyerApproved;
    bool public sellerApproved;
    address payable public buyer;
    address payable public seller;

    mapping(address => uint256) public amountDeposited;

    ///
    /// EVENTS
    ///

    event EthLocker_AmountReceived(uint256 weiAmount);
    event EthLocker_BuyerReady();
    event EthLocker_BuyerUpdated(address newBuyer);
    event EthLocker_DepositedAmountTransferred(
        address receiver,
        uint256 amount
    );
    event EthLocker_DepositInEscrow(address depositor);
    event EthLocker_Deployed(
        bool refundable,
        bool openOffer,
        uint256 deposit,
        uint256 totalAmount,
        uint256 expirationTime,
        address seller,
        address buyer
    );
    event EthLocker_DeployedCondition(
        address dataFeedProxy,
        ValueCondition valueCondition,
        int224 minimumValue,
        int224 maximumValue
    );
    event EthLocker_Expired();
    // emit indexed effective time of execution for ease of log collection, plus valueCondition value & value-reading oracle proxy contract (if applicable)
    event EthLocker_Executed(
        uint256 indexed effectiveTime,
        int224 valueCondition,
        address dataFeedProxy
    );
    event EthLocker_TotalAmountInEscrow();
    event EthLocker_SellerReady();
    event EthLocker_SellerUpdated(address newSeller);

    ///
    /// ERRORS
    ///

    error EthLocker_BalanceExceedsTotalAmount();
    error EthLocker_DepositGreaterThanTotalAmount();
    error EthLocker_IsExpired();
    error EthLocker_NotReadyToExecute();
    error EthLocker_NotBuyer();
    error EthLocker_NotSeller();
    error EthLocker_OnlyOpenOffer();
    error EthLocker_ValueConditionConflict();
    error EthLocker_ValueOlderThanOneDay();
    error EthLocker_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    /// @notice constructs the EthLocker smart escrow contract. Arranger MUST verify that the _dataFeedProxyAddress is accurate if '_valueCondition' != 0, as neither address(this) nor the ChainLockerFactory.sol contract perform such check.
    /// @param _refundable: whether the '_deposit' is refundable to the 'buyer' in the event escrow expires without executing
    /// @param _openOffer: whether this escrow is open to any prospective 'buyer' (revocable at seller's option). A 'buyer' assents by sending 'deposit' to address(this) after deployment
    /** @param _valueCondition: uint8 corresponding to the ValueCondition enum (passed as 0, 1, 2, or 3), which is the value contingency (via oracle) which must be satisfied for the ChainLocker to release. Options are 0, 1, 2, or 3, which
     *** respectively correspond to: none, <=, >=, or two conditions (both <= and >=, for the '_maximumValue' and '_minimumValue' params, respectively).
     *** For an **EXACT** value condition (i.e. that the returned value must equal an exact number), pass '3' (Both) and pass such exact required value as both '_minimumValue' and '_maximumValue'
     *** Passed as uint8 rather than enum for easier composability */
    /// @param _maximumValue: the maximum permitted int224 value returned from the applicable dAPI / API3 data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 2.
    /// @param _minimumValue: the minimum permitted int224 value returned from the applicable dAPI / API3 data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 1.
    /// @param _deposit: deposit amount in wei, which must be <= '_totalAmount' (< for partial deposit, == for full deposit)
    /// @param _totalAmount: total amount in wei which will be deposited in this contract, ultimately intended for '_seller'
    /// @param _expirationTime: _expirationTime in seconds (Unix time), which will be compared against block.timestamp. input type(uint256).max for no expiry (not recommended, as funds will only be released upon execution or if seller rejects depositor -- refunds only process at expiry)
    /// @param _seller: the seller's address, recipient of the '_totalAmount' if the contract executes
    /// @param _buyer: the buyer's address, who will cause the '_totalAmount' to be transferred to this address. Ignored if 'openOffer'
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
        address payable _seller,
        address payable _buyer,
        address _dataFeedProxyAddress
    ) payable {
        if (_deposit > _totalAmount)
            revert EthLocker_DepositGreaterThanTotalAmount();
        if (_totalAmount == 0) revert EthLocker_ZeroAmount();
        if (_expirationTime <= block.timestamp) revert EthLocker_IsExpired();
        // '_valueCondition' cannot be > 3, nor can '_maximumValue' be < '_minimumValue' if _valueCondition == 3 (ValueCondition.Both)
        if (
            _valueCondition > 3 ||
            (_valueCondition == 3 && _maximumValue < _minimumValue)
        ) revert EthLocker_ValueConditionConflict();

        if (!_openOffer) buyer = _buyer;
        refundable = _refundable;
        openOffer = _openOffer;
        valueCondition = ValueCondition(_valueCondition);
        maximumValue = _maximumValue;
        minimumValue = _minimumValue;
        deposit = _deposit;
        totalAmount = _totalAmount;
        seller = _seller;
        expirationTime = _expirationTime;
        dataFeedProxy = IProxy(_dataFeedProxyAddress);

        emit EthLocker_Deployed(
            _refundable,
            _openOffer,
            _deposit,
            _totalAmount,
            _expirationTime,
            _seller,
            _buyer
        );
        // if execution is contingent upon a value or values, emit relevant information
        if (_valueCondition != 0)
            emit EthLocker_DeployedCondition(
                _dataFeedProxyAddress,
                valueCondition,
                _minimumValue,
                _maximumValue
            );
    }

    /// @notice deposit value simply by sending 'msg.value' to 'address(this)'
    /** @dev max msg.value limit of 'totalAmount', and if 'totalAmount' is already held or escrow has expired, revert. Updates boolean and emits event when 'deposit' reached
     ** also updates 'buyer' to msg.sender if true 'openOffer' and false 'deposited', and
     ** records amount deposited by msg.sender in case of refundability or where 'seller' rejects a 'buyer' and buyer's deposited amount is to be returned  */
    receive() external payable {
        if (address(this).balance > totalAmount)
            revert EthLocker_BalanceExceedsTotalAmount();
        if (expirationTime <= block.timestamp) revert EthLocker_IsExpired();

        if (address(this).balance >= deposit && !deposited) {
            // if this EthLocker is an open offer and was not yet accepted (thus '!deposited'), make depositing address the 'buyer' and update 'deposited' to true
            if (openOffer) {
                buyer = payable(msg.sender);
                emit EthLocker_BuyerUpdated(msg.sender);
            }
            deposited = true;
            emit EthLocker_DepositInEscrow(msg.sender);
        }
        if (address(this).balance == totalAmount)
            emit EthLocker_TotalAmountInEscrow();
        amountDeposited[msg.sender] += msg.value;
        emit EthLocker_AmountReceived(msg.value);
    }

    /// @notice for the current seller to designate a new recipient address
    /// @param _seller: new recipient address of seller
    function updateSeller(address payable _seller) external {
        if (msg.sender != seller) revert EthLocker_NotSeller();

        if (!checkIfExpired()) {
            seller = _seller;
            emit EthLocker_SellerUpdated(_seller);
        }
    }

    /// @notice for the current 'buyer' to designate a new buyer address
    /// @param _buyer: new address of buyer
    function updateBuyer(address payable _buyer) external {
        if (msg.sender != buyer) revert EthLocker_NotBuyer();

        if (!checkIfExpired()) {
            buyer = _buyer;
            emit EthLocker_BuyerUpdated(_buyer);
        }
    }

    /// @notice seller and buyer each call this when ready to execute the ChainLocker; other address callers will have no effect
    /// @dev no need for an address(this).balance check because (1) a reasonable seller will only pass 'true'
    /// if 'totalAmount' is in place, and (2) 'execute()' requires address(this).balance >= 'totalAmount'
    /// separate conditionals in case 'buyer' == 'seller'
    function readyToExecute() external {
        if (msg.sender == seller) {
            sellerApproved = true;
            emit EthLocker_SellerReady();
        }
        if (msg.sender == buyer) {
            buyerApproved = true;
            emit EthLocker_BuyerReady();
        }
    }

    /** @notice callable by any external address: checks if both buyer and seller are ready to execute and expiration has not been met;
     *** if so, this contract executes and transfers 'totalAmount' to 'seller'; if not, totalAmount deposit returned to buyer (if refundable) **/
    /** @dev requires entire 'totalAmount' be held by address(this). If properly executes, pays seller and emits event with effective time of execution.
     *** Does not require amountDeposited[buyer] == address(this).balance to allow buyer to deposit from multiple addresses if desired */
    function execute() external nonReentrant {
        if (
            !sellerApproved ||
            !buyerApproved ||
            address(this).balance < totalAmount
        ) revert EthLocker_NotReadyToExecute();
        int224 _value;
        // only perform these checks if ChainLocker execution is contingent upon specified external value condition(s)
        if (valueCondition != ValueCondition.None) {
            (int224 _returnedValue, uint32 _timestamp) = dataFeedProxy.read();
            // require a value update within the last day
            if (block.timestamp - _timestamp > ONE_DAY)
                revert EthLocker_ValueOlderThanOneDay();

            if (
                (valueCondition == ValueCondition.LessThanOrEqual &&
                    _returnedValue > maximumValue) ||
                (valueCondition == ValueCondition.GreaterThanOrEqual &&
                    _returnedValue < minimumValue) ||
                (valueCondition == ValueCondition.Both &&
                    (_returnedValue > maximumValue ||
                        _returnedValue < minimumValue))
            ) revert EthLocker_ValueConditionConflict();
            // if no reversion, store the '_returnedValue' and proceed with execution
            else _value = _returnedValue;
        }

        // delete approvals
        delete sellerApproved;
        delete buyerApproved;

        if (!checkIfExpired()) {
            delete deposited;
            delete amountDeposited[buyer];
            // safeTransfer 'totalAmount' to 'seller' since 'receive()' prevents depositing more than the totalAmount, and safeguarded by any excess balance being returned to buyer after expiry in 'checkIfExpired()'
            safeTransferETH(seller, totalAmount);

            // effective time of execution is block.timestamp upon payment to seller
            emit EthLocker_Executed(
                block.timestamp,
                _value,
                address(dataFeedProxy)
            );
            emit EthLocker_DepositedAmountTransferred(seller, totalAmount);
        }
    }

    /// @notice convenience function to get a USD value receipt if a dAPI / data feed proxy exists for ETH, for example for 'seller' to submit 'totalAmount' immediately after execution/release of this EthLocker
    /// @dev external call will revert if price quote is too stale or if token is not supported; event containing '_paymentId' and '_usdValue' emitted by Receipt.sol. address(0) hard-coded for tokenContract, as native gas token price is sought
    /// @param _weiAmount: amount of wei for which caller is seeking the total USD value receipt (for example, 'totalAmount' or 'deposit')
    function getReceipt(
        uint256 _weiAmount
    ) external returns (uint256 _paymentId, uint256 _usdValue) {
        return RECEIPT.printReceipt(address(0), _weiAmount);
    }

    /// @notice for an openOffer 'seller' to reject a 'buyer' or any other address and cause the return of their deposited amount (such as one that sent < 'deposit' ETH)
    /// @param _depositor: address for reimbursement in addition to 'buyer' (if 'deposited'). If buyer sent < 'deposit' ETH to address(this), 'seller' should pass 'buyer' address here
    /** @dev deletes 'buyer' and buyer's 'amountDeposited', returning applicable funds, and resets the 'deposited' and 'buyer' variables to re-open the offer if deposit was in place.
     ** also permits seller to return deposited amount to an address that sent < 'deposit' ETH to address(this) */
    function rejectDepositor(address payable _depositor) external nonReentrant {
        if (msg.sender != seller) revert EthLocker_NotSeller();
        if (!openOffer) revert EthLocker_OnlyOpenOffer();
        // reset 'deposited' and 'buyer' variables if 'seller' passed 'buyer' as '_depositor'
        if (_depositor == buyer) {
            delete deposited;
            delete buyer;
            emit EthLocker_BuyerUpdated(address(0));
        }
        uint256 _depositAmount = amountDeposited[_depositor];
        // regardless of whether '_depositor' is 'buyer', if the address has a positive deposited balance, return it to them
        if (_depositAmount > 0) {
            delete amountDeposited[_depositor];
            safeTransferETH(_depositor, _depositAmount);
            emit EthLocker_DepositedAmountTransferred(
                _depositor,
                _depositAmount
            );
        }
    }

    /// @notice check if expired, and if so, handle refunds/transfers
    /// @dev if expired, update 'isExpired', 'deposited', and 'amountDeposited' and if non-refundable, send deposit to seller before returning balance to buyer. If refundable, send entire balance back to buyer
    /// @return isExpired
    function checkIfExpired() public nonReentrant returns (bool) {
        if (expirationTime <= block.timestamp) {
            isExpired = true;
            bool _isDeposited = deposited;

            emit EthLocker_Expired();

            delete deposited;
            delete amountDeposited[buyer];

            if (address(this).balance > 0) {
                // if non-refundable deposit and 'deposit' hasn't been reset to 'false' by a successful 'execute()', send seller the 'deposit' amount before returning the remaining escrowed amount to buyer
                if (!refundable && _isDeposited) {
                    uint256 _remainder = address(this).balance - deposit;
                    safeTransferETH(seller, deposit);
                    if (_remainder > 0) safeTransferETH(buyer, _remainder);
                    emit EthLocker_DepositedAmountTransferred(seller, deposit);
                    emit EthLocker_DepositedAmountTransferred(
                        buyer,
                        _remainder
                    );
                } else {
                    safeTransferETH(buyer, address(this).balance);
                    emit EthLocker_DepositedAmountTransferred(
                        buyer,
                        address(this).balance
                    );
                }
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
