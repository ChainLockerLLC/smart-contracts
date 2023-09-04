// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ITokenLocker {
    function checkIfExpired() external returns (bool);

    /// @dev msg.sender must have approved the TokenLocker address for 'amount' in the applicable ERC20 token contract
    function depositTokens(uint256 amount) external;

    function depositTokensWithPermit(
        address depositor,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function execute() external;

    // returns paymentId and USD value
    function getReceipt(
        uint256 tokenAmount
    ) external returns (uint256, uint256);

    function readyToExecute() external;

    /// @dev only callable by current 'seller'
    function rejectDepositor(address depositor) external;

    /// @dev only callable by current 'buyer'
    function updateBuyer(address buyer) external;

    /// @dev only callable by current 'seller'
    function updateSeller(address seller) external;

    function withdraw() external;
}