// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {BasicRandomizer} from "@artblocks/BasicRandomizer.sol";
import {GenArt721CoreV2_PBAB} from "@artblocks/engine/GenArt721CoreV2_PBAB.sol";
import "../src/MinterDAExpSettl_Simplified.sol";
import "../src/AllowanceBasedMinter_AB.sol";
import "../src/Test/FakeMinter.sol";
import "@std/Test.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is default deployer 
 */

contract SwitchMintersTest is Test {

    using ECDSA for bytes32;
    
    BasicRandomizer randomizer;
    GenArt721CoreV2_PBAB main721Contract;
    MinterDAExpSettl_Simplified minterDA;
    AllowanceBasedMinter_AB minterAL;

    FakeMinter fakeMinter;

    address artistAddress;
    address managerAddress;
    address customer;

    uint256 allowanceSignerPrivateKey;
    address allowanceSignerAddress;

    address deployer;
    address abWallet;
    address hodlersMultisig;

    uint256 auctionStartTime;
    uint256 priceDecayHalfLifeSeconds;
    uint256 startPrice = 1e18;
    uint256 basePrice = 1e17;

    uint256 currentAllowanceId;

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
        
        minterDA = new MinterDAExpSettl_Simplified(address(main721Contract), abWallet, hodlersMultisig);

        allowanceSignerPrivateKey = 0x4a5113;
        allowanceSignerAddress = vm.addr(allowanceSignerPrivateKey);
        minterAL = new AllowanceBasedMinter_AB(address(main721Contract), abWallet, hodlersMultisig);
        minterAL.setAllowancesSigner(allowanceSignerAddress);

        minterAL.setCurProjectId(startingProjectId);
        minterAL.setPrice(1e17);

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

    function testCanNotMintUntilMinterIsWhitelisted() public {
        
        uint256 projectId = 0;

        activateProject(projectId);

        setupDefaultAuction(projectId);

        (, uint256 tokenPriceInWei, , ) = minterDA.getPriceInfo(projectId);    

        assertFalse(main721Contract.isMintWhitelisted(address(minterDA)));

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.startPrank(customer);
        vm.expectRevert("Must mint from whitelisted minter contract.");
        minterDA.purchase{value: tokenPriceInWei}(projectId);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(customer), 0);
    }

    function testCanMintFromBothMintersOneByOneButNotFromMaliciousMinter() public {
        
        uint256 projectId = 0;

        activateProject(projectId);
        setupDefaultAuction(projectId);

        (, uint256 tokenPriceInWei, , ) = minterDA.getPriceInfo(projectId);    

        vm.prank(deployer);
        main721Contract.addMintWhitelisted(address(minterDA));

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minterDA.purchase{value: tokenPriceInWei}(projectId);

        assertEq(main721Contract.balanceOf(customer), 1);

        vm.startPrank(deployer);
        main721Contract.removeMintWhitelisted(address(minterDA));
        main721Contract.addMintWhitelisted(address(minterAL));
        vm.stopPrank();

        assertFalse(main721Contract.isMintWhitelisted(address(minterDA)));
        assertTrue(main721Contract.isMintWhitelisted(address(minterAL)));

        uint256 alPrice = minterAL.price();

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        vm.prank(customer);
        minterAL.order{value: alPrice}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 2);

        fakeMinter = new FakeMinter(address(main721Contract));
        vm.expectRevert("Must mint from whitelisted minter contract.");
        fakeMinter.mint(address(0xda5c), projectId);

        assertEq(main721Contract.balanceOf(address(0xda5c)), 0);
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
        minterDA.setAuctionDetails(
            projectId,
            auctionStartTime,
            priceDecayHalfLifeSeconds,    
            startPrice,    
            basePrice    
        );
    }
    
    function buildAndSign(address _customer) internal 
        returns (uint256 nonce, bytes memory signature) {
            nonce = currentAllowanceId++;
            bytes32 hashToSign = (minterAL.createMessage(_customer, nonce)).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(allowanceSignerPrivateKey , hashToSign);
            signature = abi.encodePacked(r,s,v);
    }

}