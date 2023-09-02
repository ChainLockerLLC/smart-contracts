// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IReceipt {
    // getter for the 'paymentIdToUsdValue' mapping; returns the USD value for a passed 'paymentId'
    function paymentIdToUsdValue(
        uint256 paymentId
    ) external view returns (uint256);

    // getter for the 'tokenToProxy' mapping; returns the data feed proxy contract for the applicable token's USD price
    function tokenToProxy(
        address tokenContract
    ) external view returns (address);

    // returns paymentId and USD value
    function printReceipt(
        address token,
        uint256 tokenAmount,
        uint256 decimals
    ) external returns (uint256, uint256);
}
