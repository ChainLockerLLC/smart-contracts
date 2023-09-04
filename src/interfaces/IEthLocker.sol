// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/// @dev deposits are handled by EthLocker's 'receive()' function when sending msg.value to the EthLocker address
interface IEthLocker {
    function checkIfExpired() external returns (bool);

    function execute() external;

    // returns paymentId and USD value
    function getReceipt(
        uint256 weiAmount
    ) external returns (uint256, uint256);

    function readyToExecute() external;

    /// @dev only callable by current 'seller'
    function rejectDepositor(address payable depositor) external;

    /// @dev only callable by current 'buyer'
    function updateBuyer(address payable buyer) external;

    /// @dev only callable by current 'seller'
    function updateSeller(address payable seller) external;

    function withdraw() external;
}