//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * this solidity file is provided as-is; no guarantee, representation or warranty is being made, express or implied,
 * as to the safety or correctness of the code or any smart contracts or other software deployed from these files.
 * '_seller', '_buyer', '_deposit', '_refundable', '_openOffer' and other terminology herein is used only for simplicity and convenience of reference, and
 * should not be interpreted to ascribe, intend, nor imply any legal status, agreement, nor relationship between or among any author, modifier, deployer, participant, or other relevant user hereto
 **/

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

/////// o=o=o=o=o ChainLocker Factory o=o=o=o=o \\\\\\\

// O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O=o=O \\

import {SafeTransferLib, ReentrancyGuard, EthLocker} from "./EthLocker.sol";
import {
    IERC20Permit,
    SafeTransferLib as TokenSafeTransferLib,
    TokenLocker
} from "./TokenLocker.sol";

interface IERC20 {
    function decimals() external view returns (uint256);
}

/// @notice Chainalysis's sanctions oracle, to prevent sanctioned addresses from calling 'deployChainLocker' and thus deploying a ChainLocker/paying deployment fee to 'receiver'
/// @author Chainalysis (see: https://go.chainalysis.com/chainalysis-oracle-docs.html)
/// @dev note this programmatic check is in addition to several token-specific sanctions checks
interface ISanctionsOracle {
    function isSanctioned(address addr) external view returns (bool);
}

/**
 * @title       o=o=o=o=o ChainLockerFactory o=o=o=o=o
 **/
/**
 * @author      o=o=o=o=o ChainLocker LLC o=o=o=o=o
 **/
/**
 * @notice ChainLocker factory contract, which enables a caller of 'deployChainLocker' to deploy a ChainLocker with their chosen parameters
 **/
contract ChainLockerFactory {
    /** @notice 'ValueCondition' enum values represent the following:
     *** 0 ('None'): no value contingency to ChainLocker execution; '_maximumValue', '_minimumValue' and '_dataFeedProxyAddress' params are ignored.
     *** 1 ('LessThanOrEqual'): the value returned from '_dataFeedProxyAddress' in the deployed ChainLocker must be <= '_maximumValue'; '_minimumValue' param is ignored
     *** 2 ('GreaterThanOrEqual'): the value returned from '_dataFeedProxyAddress' in the deployed ChainLocker must be >= '_minimumValue'; '_maximumValue' param is ignored
     *** 3 ('Both'): the value returned from '_dataFeedProxyAddress' in the deployed ChainLocker must be both <= '_maximumValue' and >= '_minimumValue'
     */
    enum ValueCondition {
        None,
        LessThanOrEqual,
        GreaterThanOrEqual,
        Both
    }

    /// @notice Chainalysis Inc.'s Ethereum mainnet sanctions oracle, see https://go.chainalysis.com/chainalysis-oracle-docs.html for contract addresses
    ISanctionsOracle internal constant sanctionCheck =
        ISanctionsOracle(0x40C57923924B5c5c5455c48D93317139ADDaC8fb);

    /// @notice address which may update the fee parameters and receives any fees if 'feeSwitch' == true
    address payable public receiver;
    address payable private _pendingReceiver;

    /// @notice whether a fee is payable for using 'deployChainLocker()'
    bool public feeSwitch;

    /// @notice number by which the user's submitted '_totalAmount' is divided in order to calculate the fee, if 'feeSwitch' == true
    uint256 public feeDenominator;

    /// @notice minimum fee amount for a user calling 'deployChainLocker()' if 'feeSwitch' == true
    uint256 public minimumFee;

    ///
    /// EVENTS
    ///

    event ChainLockerFactory_Deployment(
        address indexed deployer,
        address indexed chainLockerAddress,
        address tokenContract
    );

    event ChainLockerFactory_FeePaid(uint256 feeAmount);

    event ChainLockerFactory_FeeUpdate(
        bool feeSwitch,
        uint256 newFeeDenominator,
        uint256 newMinimumFee
    );

    event ChainLockerFactory_ReceiverUpdate(address newReceiver);

    ///
    /// ERRORS
    ///

    error ChainLockerFactory_DeployerSanctioned();
    error ChainLockerFactory_FeeMissing();
    error ChainLockerFactory_OnlyReceiver();
    error ChainLockerFactory_ZeroInput();

    ///
    /// FUNCTIONS
    ///

    /** @dev enable optimization with >= 200 runs; 'msg.sender' is the initial 'receiver';
     ** constructor is payable for gas optimization purposes but msg.value should == 0. */
    constructor() payable {
        receiver = payable(msg.sender);
        // avoid a zero denominator, though there is also such a check in 'updateFee()'
        feeDenominator = 1;
    }

    /** @notice for a user to deploy their own ChainLocker, with a msg.value fee in wei if 'feeSwitch' == true. Note that electing a custom '_valueCondition' introduces
     ** execution reliance upon external oracle-fed data from the user's submitted '_dataFeedProxyAddress', but otherwise the deployed ChainLocker will be entirely immutable save for 'seller' and 'buyer' having the ability to update their own addresses. */
    /** @dev the various applicable input validations/condition checks for deployment of a ChainLocker are in the prospective contracts rather than this factory,
     ** except this function ensures the msg.sender is not sanctioned, as it may be paying a deployment fee to the 'receiver'. Fee (if 'feeSwitch' == true) is calculated on the basis of (decimal-accounted) raw amount with a hard-coded minimum, rather than introducing price oracle dependency here;
     ** '_deposit', '_seller' and '_buyer' nomenclature used for clarity (rather than payee and payor or other alternatives),
     ** though intended purpose of the ChainLocker is the user's choice; see comments above and in documentation.
     ** The constructor of each deployed ChainLocker contains more detailed event emissions */
    /// @param _refundable: whether the '_deposit' for the ChainLocker should be refundable to the applicable 'buyer' (true) or non-refundable (false) in the event the ChainLocker expires (reaches '_expirationTime') without executing.
    /// @param _openOffer: whether the ChainLocker is open to any prospective 'buyer' (with any specific 'buyer' rejectable at seller's option).
    /** @param _valueCondition: ValueCondition enum, which is the value contingency (via oracle) which must be satisfied for the ChainLocker to release.
     *** Options are none ('0'), <= ('1'), >= ('2'), or either precisely == or within two values ('3', both <= and >=, for the '_maximumValue' and '_minimumValue' params, respectively). */
    /// @param _maximumValue: the maximum returned int224 value from the applicable data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 2.
    /// @param _minimumValue: the minimum returned int224 value from the applicable data feed upon which the ChainLocker's execution is conditioned. Ignored if '_valueCondition' == 0 or _valueCondition == 1.
    /// @param _deposit: deposit amount in wei or tokens (if EthLocker or TokenLocker is deployed, respectively), which must be <= '_totalAmount' (< for partial deposit, == for full deposit).
    /// @param _totalAmount: total amount of wei or tokens (if EthLocker or TokenLocker is deployed, respectively) which will be transferred to and locked in the deployed ChainLocker.
    /// @param _expirationTime: time of the ChainLocker's expiry, provided in seconds (Unix time), which will be compared against block.timestamp.
    /// @param _seller: the contractor/payee/seller's address, as intended ultimate recipient of the locked '_totalAmount' should the ChainLocker successfully execute without expiry. Also receives '_deposit' at '_expirationTime' regardless of execution if '_refundable' == false.
    /// @param _buyer: the client/payor/buyer's address, who will cause the '_totalAmount' to be transferred to the deployed ChainLocker's address. Ignored if 'openOffer' == true.
    /// @param _tokenContract: contract address for the ERC20-compliant token used when deploying a TokenLocker; if deploying an EthLocker, pass address(0).
    /// @param _dataFeedProxyAddress: contract address for the proxy that will read the data feed for the '_valueCondition' query. Ignored if '_valueCondition' == 0. User calling this method should ensure the managed feed subscription, or applicable sponsor wallet, is sufficiently funded for their intended purposes.
    function deployChainLocker(
        bool _refundable,
        bool _openOffer,
        ValueCondition _valueCondition,
        int224 _maximumValue,
        int224 _minimumValue,
        uint256 _deposit,
        uint256 _totalAmount,
        uint256 _expirationTime,
        address payable _seller,
        address payable _buyer,
        address _tokenContract,
        address _dataFeedProxyAddress
    ) external payable returns (address) {
        if (sanctionCheck.isSanctioned(msg.sender))
            revert ChainLockerFactory_DeployerSanctioned();
        uint8 _condition = uint8(_valueCondition);

        // if 'feeSwitch' == true, calculate fee based on '_totalAmount', adjusting if ERC20 token's decimals is != 18 (if applicable)
        // if no necessary adjustment or if decimals returns 0, '_adjustedAmount' will remain == '_totalAmount'
        if (feeSwitch) {
            uint256 _fee;
            uint256 _adjustedAmount = _totalAmount;
            if (_tokenContract != address(0)) {
                uint256 _decimals = IERC20(_tokenContract).decimals();
                // if more than 18 decimals, divide the total amount by the excess decimal places; subtraction will not underflow due to condition check
                if (_decimals > 18) {
                    unchecked {
                        _adjustedAmount = (_totalAmount /
                            10 ** (_decimals - 18));
                    }
                }
                // if less than 18 decimals, multiple the total amount by the difference in decimal places
                else if (_decimals < 18) {
                    _adjustedAmount = _totalAmount * (10 ** (18 - _decimals));
                }
            }
            // 'feeDenominator' cannot == 0, and '_adjustedAmount' cannot be > max uint256 || < 0, no overflow or underflow risk
            unchecked {
                _fee = _adjustedAmount / feeDenominator;
            }
            if (_fee < minimumFee) _fee = minimumFee;

            // revert if the 'msg.value' is insufficient to cover the fee, or if the transfer of the fee to 'receiver' fails
            (bool success, ) = receiver.call{value: msg.value}("");
            if (msg.value < _fee || !success)
                revert ChainLockerFactory_FeeMissing();
            emit ChainLockerFactory_FeePaid(msg.value);
        }

        if (_tokenContract == address(0)) {
            EthLocker _newEthLocker = new EthLocker(
                _refundable,
                _openOffer,
                _condition,
                _maximumValue,
                _minimumValue,
                _deposit,
                _totalAmount,
                _expirationTime,
                _seller,
                _buyer,
                _dataFeedProxyAddress
            );
            emit ChainLockerFactory_Deployment(
                msg.sender,
                address(_newEthLocker),
                address(0)
            );
            return address(_newEthLocker);
        } else {
            TokenLocker _newTokenLocker = new TokenLocker(
                _refundable,
                _openOffer,
                _condition,
                _maximumValue,
                _minimumValue,
                _deposit,
                _totalAmount,
                _expirationTime,
                _seller,
                _buyer,
                _tokenContract,
                _dataFeedProxyAddress
            );
            emit ChainLockerFactory_Deployment(
                msg.sender,
                address(_newTokenLocker),
                _tokenContract
            );
            return address(_newTokenLocker);
        }
    }

    /// @notice allows the receiver to toggle the fee switch, and update the 'feeDenominator' and 'minimumFee'
    /// @param _feeSwitch: boolean fee toggle for 'deployChainLocker()' (true == fees on, false == no fees)
    /// @param _newFeeDenominator: nonzero number by which a user's submitted '_totalAmount' will be divided in order to calculate the fee, updating the 'feeDenominator' variable; 10e14 corresponds to a 0.1% fee, 10e15 for 1%, etc. (fee calculations in 'deployChainlocker()' are 18 decimals)
    /// @param _newMinimumFee: minimum fee for a user's call to 'deployChainLocker()', which must be > 0
    function updateFee(
        bool _feeSwitch,
        uint256 _newFeeDenominator,
        uint256 _newMinimumFee
    ) external {
        if (msg.sender != receiver) revert ChainLockerFactory_OnlyReceiver();
        if (_newFeeDenominator == 0) revert ChainLockerFactory_ZeroInput();
        feeSwitch = _feeSwitch;
        feeDenominator = _newFeeDenominator;
        minimumFee = _newMinimumFee;

        emit ChainLockerFactory_FeeUpdate(
            _feeSwitch,
            _newFeeDenominator,
            _newMinimumFee
        );
    }

    /// @notice allows the 'receiver' to replace their address. First step in two-step address change.
    /// @dev use care in updating 'receiver' to a contract with complex receive() function due to the 'call' usage in this contract
    /// @param _newReceiver: new payable address for pending 'receiver', who must accept the role by calling 'acceptReceiverRole'
    function updateReceiver(address payable _newReceiver) external {
        if (msg.sender != receiver) revert ChainLockerFactory_OnlyReceiver();
        _pendingReceiver = _newReceiver;
    }

    /// @notice for the pending new receiver to accept the role transfer.
    /// @dev access restricted to the address stored as '_pendingReceiver' to accept the two-step change. Transfers 'receiver' role to the caller and deletes '_pendingReceiver' to reset.
    function acceptReceiverRole() external {
        address payable _sender = payable(msg.sender);
        if (_sender != _pendingReceiver) {
            revert ChainLockerFactory_OnlyReceiver();
        }
        delete _pendingReceiver;
        receiver = _sender;
        emit ChainLockerFactory_ReceiverUpdate(_sender);
    }
}
