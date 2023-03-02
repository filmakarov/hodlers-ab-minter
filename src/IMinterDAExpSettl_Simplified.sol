// SPDX-License-Identifier: LGPL-3.0-only
// Created By: Art Blocks Inc.

pragma solidity ^0.8.0;

import {IFilteredMinterDAExpV0} from "@artblocks/interfaces/0.8.x/IFilteredMinterDAExpV0.sol";

/**
 * @title This interface is a mixin for IFilteredMinterExpSettlementV<version>
 * interfaces to use when defining settlement minter interfaces.
 * @author Art Blocks Inc.
 */
interface IMinterDAExpSettl_Simplified is IFilteredMinterDAExpV0 {
    /// Auction details cleared for project `projectId`.
    /// At time of reset, the project has had `numPurchases` purchases on this
    /// minter, with a most recent purchase price of `latestPurchasePrice`. If
    /// the number of purchases is 0, the latest purchase price will have a
    /// dummy value of 0.
    event ResetAuctionDetails(
        uint256 indexed projectId,
        uint256 numPurchases,
        uint256 latestPurchasePrice
    );

    /// sellout price updated for project `projectId`.
    /// @dev does not use generic event because likely will trigger additional
    /// actions in indexing layer
    event SelloutPriceUpdated(
        uint256 indexed _projectId,
        uint256 _selloutPrice
    );

    /// artist and admin have withdrawn revenues from settleable purchases for
    /// project `projectId`.
    /// @dev does not use generic event because likely will trigger additional
    /// actions in indexing layer
    event ArtistAndAdminRevenuesWithdrawn(uint256 indexed _projectId);

    /// receipt has an updated state
    event ReceiptUpdated(
        address indexed _purchaser,
        uint256 indexed _projectId,
        uint256 _numPurchased,
        uint256 _netPosted
    );

     /**
     * @notice Local max invocations for project `_projectId`, tied to core contract `_coreContractAddress`,
     * updated to `_maxInvocations`.
     */
    event ProjectMaxInvocationsLimitUpdated(
        uint256 indexed _projectId,
        uint256 _maxInvocations
    );

    // Sets the local max invocations for a given project, checking that the provided max invocations is
    // less than or equal to the global max invocations for the project set on the core contract.
    // This does not impact the max invocations value defined on the core contract.
    function manuallyLimitProjectMaxInvocations(
        uint256 _projectId,
        uint256 _maxInvocations
    ) external;

    /// returns latest purchase price for project `_projectId`, or 0 if no
    /// purchases have been made.
    function getProjectLatestPurchasePrice(
        uint256 _projectId
    ) external view returns (uint256 latestPurchasePrice);

    /// returns the number of settleable invocations for project `_projectId`.
    function getNumSettleableInvocations(
        uint256 _projectId
    ) external view returns (uint256 numSettleableInvocations);

    /// Returns the current excess settlement funds on project `_projectId`
    /// for address `_walletAddress`.
    function getProjectExcessSettlementFunds(
        uint256 _projectId,
        address _walletAddress
    ) external view returns (uint256 excessSettlementFundsInWei);
}
