// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IChainLockerFactory {
    enum ValueCondition {
        None,
        LessThanOrEqual,
        GreaterThanOrEqual,
        Both
    }

    function deployChainLocker(
        bool refundable,
        bool openOffer,
        ValueCondition valueCondition,
        int224 maximumValue,
        int224 minimumValue,
        uint256 deposit,
        uint256 totalAmount,
        uint256 expirationTime,
        address payable seller,
        address payable buyer,
        address tokenContract,
        address dataFeedProxyAddress
    ) external payable returns (address);
}
