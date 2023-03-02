// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {BasicRandomizer} from "@artblocks/BasicRandomizer.sol";
import {GenArt721CoreV2_PBAB} from "@artblocks/engine/GenArt721CoreV2_PBAB.sol";
import "../src/MinterDAExpSettl_Simplified.sol";
import "@std/Test.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is default deployer 
 */

contract DATest is Test {

    using ECDSA for bytes32;
    
    BasicRandomizer randomizer;
    GenArt721CoreV2_PBAB main721Contract;
    MinterDAExpSettl_Simplified minter;

    address artistAddress;
    address managerAddress;
    address customer;

    address deployer;
    address abWallet;
    address hodlersMultisig;

    uint256 auctionStartTime;
    uint256 priceDecayHalfLifeSeconds;
    uint256 startPrice = 1e18;
    uint256 basePrice = 1e17;

    mapping (address => uint256) totalSent;

    function setUp() public {

        deployer = address(0xde9104e5);
        vm.deal(deployer, 1e21);

        abWallet = address(0xa121b10c5);
        hodlersMultisig = address(0x60d1e125);

        // Deploy contracts
        vm.startPrank(deployer);
        uint256 startingProjectId = 0;
        randomizer = new BasicRandomizer();
        main721Contract = new GenArt721CoreV2_PBAB("HodlersCollective", "HDC", address(randomizer), startingProjectId);
        
        minter = new MinterDAExpSettl_Simplified(address(main721Contract), abWallet, hodlersMultisig);
        
        main721Contract.addMintWhitelisted(address(minter));

        // Setup first AB project 
        managerAddress = address(0xa11ce);
        artistAddress = address(0xdeafbeef);

        main721Contract.addWhitelisted(managerAddress);
        vm.stopPrank();

        vm.prank(managerAddress);
        main721Contract.addProject("Genesis", payable(artistAddress), 1e17);

        customer = address(0xdecaf);
        vm.deal(customer, 100*1e18);

        auctionStartTime = 1002603;
        priceDecayHalfLifeSeconds = 350;
        startPrice = 1e18; // 1 eth
        basePrice = 1e17; // 0.1 eth

        // for randomizer to work
        vm.roll(100);
    }

    function testCanSetTheAuctionUp() public {
        uint256 projectId = 0;
        
        activateProject(projectId);

        setupDefaultAuction(projectId);

        (uint256 auctionStartTime_set,
        uint256 priceDecayHalfLifeSeconds_set,
        uint256 startPrice_set,
        uint256 basePrice_set ) = minter.projectAuctionParameters(projectId);

        assertEq(auctionStartTime, auctionStartTime_set);
        assertEq(priceDecayHalfLifeSeconds, priceDecayHalfLifeSeconds_set);
        assertEq(startPrice, startPrice_set);
        assertEq(basePrice, basePrice_set);

        (bool isConfigured, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId); 
        assertEq(isConfigured, true);
        assertEq(tokenPriceInWei, 1e18);
    }

    function testCanNotMintUntilAuctionStarts() public {
        uint256 projectId = 0;
        
        activateProject(projectId);
        setupDefaultAuction(projectId);

        assertLt(block.timestamp, auctionStartTime);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);  

        // can not purchase before auction started
        vm.expectRevert("Auction not yet started");
        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

    }

    function testCanMint() public {
        
        uint256 projectId = 0;

        activateProject(projectId);

        setupDefaultAuction(projectId);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);    

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 1);
    }

    // can mint when everything in order
    function testCanMintSeveralTokensAndWithdrawFundsFromContract() public {
        
        uint256 projectId = 0;

        activateProject(projectId);

        setupDefaultAuction(projectId);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);    

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 1);
        totalSent[customer] += tokenPriceInWei;

        // can purchase at reduced price
        vm.warp(auctionStartTime + priceDecayHalfLifeSeconds*3);
        (, tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        //console.log("Price %i at time %i", tokenPriceInWei, block.timestamp);

        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 2);
        totalSent[customer] += tokenPriceInWei;

        // assert price settled at base price
        vm.warp(auctionStartTime + priceDecayHalfLifeSeconds*100);
        (, tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        assertEq(tokenPriceInWei, 1e17);

        uint256 lastTokenPriceInWei = tokenPriceInWei;

        // mint to some other customer
        address customer2 = address(0xdecaf2);
        vm.deal(customer2, 1e21);
        vm.prank(customer2);
        minter.purchase{value: tokenPriceInWei}(projectId);
        assertEq(main721Contract.balanceOf(customer2), 1);

        uint256 totalEarned = (lastTokenPriceInWei)*3;

        // test withdraw funds by ab and hodlers
        vm.prank(artistAddress);
        minter.withdrawArtistAndAdminRevenues(projectId);
        //console.log(abWallet.balance);
        assertEq(abWallet.balance, totalEarned/10);
        assertEq(hodlersMultisig.balance, totalEarned*9/10);

        // test refund to customer
        uint256 expectedRefund = totalSent[customer] - main721Contract.balanceOf(customer)*lastTokenPriceInWei;
        address payable refundReceiver = payable(address(0x5ef97d5ece17e5));
        assertEq(refundReceiver.balance, 0);
        vm.prank(customer);
        minter.reclaimProjectExcessSettlementFundsTo(refundReceiver, projectId);
        assertEq(refundReceiver.balance, expectedRefund);
    }

    // can mint when everything in order
    function testCanWithdrawRefundBeforeSoldoutAndThenWithdrawTheRest() public {
        
        uint256 projectId = 0;

        activateProject(projectId);

        setupDefaultAuction(projectId);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);    

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 1);
        totalSent[customer] += tokenPriceInWei;

        // can purchase at reduced price
        vm.warp(auctionStartTime + priceDecayHalfLifeSeconds*3);
        (, tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        console.log("Price %i at time %i", tokenPriceInWei, block.timestamp);

        vm.prank(customer);
        minter.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 2);
        totalSent[customer] += tokenPriceInWei;

        assertGt(tokenPriceInWei, 1e17);

        uint256 lastTokenPriceInWei = tokenPriceInWei;

        // test refund to customer
        uint256 expectedRefund = totalSent[customer] - main721Contract.balanceOf(customer)*lastTokenPriceInWei;
        address payable refundReceiver = payable(address(0x5ef97d5ece17e5));
        assertEq(refundReceiver.balance, 0);
        vm.prank(customer);
        minter.reclaimProjectExcessSettlementFundsTo(refundReceiver, projectId);
        assertEq(refundReceiver.balance, expectedRefund);
        console.log("1 ", refundReceiver.balance);

        // assert price settled at base price
        vm.warp(auctionStartTime + priceDecayHalfLifeSeconds*100);
        (, tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        assertEq(tokenPriceInWei, 1e17);
        lastTokenPriceInWei = tokenPriceInWei;

        // mint to some other customer at base price
        address customer2 = address(0xdecaf2);
        vm.deal(customer2, 1e21);
        vm.prank(customer2);
        minter.purchase{value: tokenPriceInWei}(projectId);
        assertEq(main721Contract.balanceOf(customer2), 1);

        uint256 expectedFullRefund = totalSent[customer] - main721Contract.balanceOf(customer)*lastTokenPriceInWei;
        vm.prank(customer);
        minter.reclaimProjectExcessSettlementFundsTo(refundReceiver, projectId);
        console.log("2 ", refundReceiver.balance);
        assertEq(refundReceiver.balance, expectedFullRefund);

    }


    // HELPERS

    function activateProject(uint256 _projectId) internal {
        vm.prank(managerAddress);
        main721Contract.toggleProjectIsActive(_projectId);

        vm.prank(artistAddress);
        main721Contract.toggleProjectIsPaused(_projectId);
        
        (,,,, bool isActive,,,,) = main721Contract.projectTokenInfo(_projectId); 
        (,,,, bool isPaused) = main721Contract.projectScriptInfo(_projectId);
        assertEq(isActive, true);
        assertEq(isPaused, false);
    }

    function setupDefaultAuction(uint256 projectId) internal {

        vm.prank(artistAddress);
        minter.setAuctionDetails(
            projectId,
            auctionStartTime,
            priceDecayHalfLifeSeconds,    
            startPrice,    
            basePrice    
        );
    }

}