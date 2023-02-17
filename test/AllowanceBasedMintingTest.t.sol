// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {BasicRandomizer} from "@artblocks/BasicRandomizer.sol";
import {GenArt721CoreV2_PBAB} from "@artblocks/engine/GenArt721CoreV2_PBAB.sol";
import "../src/AllowanceBasedMinter_ABV2.sol";
import "@std/Test.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is deployer 
 */

contract AllowanceBasedMintingTest is Test {

    using ECDSA for bytes32;
    
    BasicRandomizer randomizer;
    GenArt721CoreV2_PBAB main721Contract;
    AllowanceBasedMinter_ABV2 minter;

    uint256 allowanceSignerPrivateKey;
    address allowanceSignerAddress;

    address artistAddress;
    address managerAddress;
    address customer;

    uint256 currentAllowanceId;

    function setUp() public {

        // Deploy contracts
        uint256 startingProjectId = 0;
        randomizer = new BasicRandomizer();
        main721Contract = new GenArt721CoreV2_PBAB("HodlersCollective", "HDC", address(randomizer), startingProjectId);
        

        allowanceSignerPrivateKey = 0x4a5113;
        allowanceSignerAddress = vm.addr(allowanceSignerPrivateKey);
        minter = new AllowanceBasedMinter_ABV2(address(main721Contract));
        minter.setAllowancesSigner(allowanceSignerAddress);
        
        main721Contract.addMintWhitelisted(address(minter));

        // Setup first AB project 
        managerAddress = address(0xa11ce);
        artistAddress = address(0xdeafbeef);

        main721Contract.addWhitelisted(managerAddress);

        vm.prank(managerAddress);
        main721Contract.addProject("Genesis", payable(artistAddress), 1e17);

        customer = address(0xdecaf);
        vm.deal(customer, 100*1e18);

        // random #from 0 to 1000
        currentAllowanceId = (block.timestamp+ block.number) % 1000;
    }

   
    function testCanNotMintWhenNotActive() public {
        uint256 projectId = 0;
        uint256 price = 1e17;
        
        (,,,, bool isActive,,,,) = main721Contract.projectTokenInfo(projectId); 
        assertEq(isActive, false);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);

        vm.startPrank(customer);
        vm.expectRevert("Project must exist and be active");
        minter.order{value: price}(customer, nonce, signature);
        vm.stopPrank();
    }

    // can not mint when active but paused

    function testCanMint() public {
            // (,,, bool isLocked, bool isPaused) = main721Contract.projectScriptInfo(projectId);
    }

    // can not mint when wrong value sent

    // can not mint with changes in nonce  

    // can not mint with other person's signature

    // can not reuse signature

    // artist's mint only one
    
    // not artist can't mint with artistMint



    function buildAndSign(address _customer, uint256 _price, uint256 _projectId) internal view
        returns (uint256 nonce, bytes memory signature) {
            nonce = (((currentAllowanceId << 64) + _projectId) << 128) + _price;
            bytes32 hashToSign = (minter.createMessage(_customer, nonce)).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(allowanceSignerPrivateKey , hashToSign);
            signature = abi.encodePacked(r,s,v);
    }
    
    /*
    function buildAllowanceNonce(uint256 price, uint256 projectId) internal view returns(uint256 nonce) {
        nonce = (((currentAllowanceId << 64) + projectId) << 128) + price;
        //console.log("allowance id %i, projectId %i, price %i", currentAllowanceId, projectId, price);
        //console.logBytes(abi.encodePacked(nonce));
    }
    */

}