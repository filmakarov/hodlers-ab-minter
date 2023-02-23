// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {BasicRandomizer} from "@artblocks/BasicRandomizer.sol";
import {GenArt721CoreV2_PBAB} from "@artblocks/engine/GenArt721CoreV2_PBAB.sol";
import "../src/AllowanceBasedMinter_ABV2.sol";
import "@std/Test.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is default deployer 
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

    address deployer;

    uint256 currentAllowanceId;

    function setUp() public {

        deployer = address(0xde9104e5);
        vm.deal(deployer, 1e21);

        // Deploy contracts
        vm.startPrank(deployer);
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
        vm.stopPrank();

        vm.prank(managerAddress);
        main721Contract.addProject("Genesis", payable(artistAddress), 1e17);

        customer = address(0xdecaf);
        vm.deal(customer, 100*1e18);

        vm.roll(100);
        currentAllowanceId = (block.timestamp + block.number) % 1000;
    }

    // can not mint until project is active
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
    function testCanNotMintWhenActiveButPaused() public {
        uint256 projectId = 0;
        uint256 price = 1e17;

        vm.prank(managerAddress);
        main721Contract.toggleProjectIsActive(projectId);
        
        (,,,, bool isActive,,,,) = main721Contract.projectTokenInfo(projectId); 
        (,,,, bool isPaused) = main721Contract.projectScriptInfo(projectId);
        assertEq(isActive, true);
        assertEq(isPaused, true);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);

        vm.startPrank(customer);
        vm.expectRevert("Purchases are paused.");
        minter.order{value: price}(customer, nonce, signature);
        vm.stopPrank(); 
    }

    // can mint when everything in order
    function testCanMint() public {
        
        uint256 projectId = 0;
        uint256 price = 1e17;

        activateProject(projectId);

        assertEq(main721Contract.balanceOf(customer), 0);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        vm.prank(customer);
        minter.order{value: price}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);
    }

    // can not mint when wrong value sent
    function testCanNotMintWithWrongValue() public {
        
        uint256 projectId = 0;
        uint256 price = 1e17;

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        
        uint256 wrongValue = price/2;
        
        vm.startPrank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AllowanceBasedMinter_ABV2.NotEnoughValueProvided.selector, 
                price,
                wrongValue
            )
        );
        minter.order{value: wrongValue}(customer, nonce, signature);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(customer), 0);
    }

    // can not mint with changes in nonce  
    function testCanNotMintWithFakeNonce() public {
        
        uint256 projectId = 0;
        uint256 price = 1e17;

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        
        // make price 1 wei
        uint256 manipulatedNonce = nonce - price + 1; 
        
        vm.startPrank(customer);
        vm.expectRevert("!INVALID_SIGNATURE!");
        minter.order{value: 1}(customer, manipulatedNonce, signature);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(customer), 0);
    }

    // can not mint with other person's signature
    function testCanNotMintWithOtherPersonSignature() public {
        
        uint256 projectId = 0;
        uint256 price = 1e17;

        activateProject(projectId);

        address darkHacker = address(0x7ac1c35);
        vm.deal(darkHacker, 1e20);
        assertFalse(darkHacker == customer);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        
        vm.startPrank(darkHacker);
        vm.expectRevert("!INVALID_SIGNATURE!");
        minter.order{value: price}(darkHacker, nonce, signature);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(address(darkHacker)), 0);
    }

    // can not reuse signature
    function testCanNotReuseSignature() public {
        
        uint256 projectId = 0;
        uint256 price = 1e17;

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        
        vm.startPrank(customer);
        minter.order{value: price}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);

        vm.expectRevert("!ALREADY_USED!");
        minter.order{value: price}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);

        vm.stopPrank();
    }

    // artist's mint only one
    function testArtistCanMintWithinLimit() public {
        
        uint256 projectId = 0;

        vm.prank(deployer);
        minter.setArtistLimit(projectId, 1);

        (uint256 limit, uint256 minted) = minter.getArtistLimitAndMinted(projectId);
        assertEq(limit, 1);
        assertEq(minted, 0);

        vm.startPrank(artistAddress);
        minter.artistMint(artistAddress, projectId);
        assertEq(main721Contract.balanceOf(artistAddress), 1);

        (, minted) = minter.getArtistLimitAndMinted(projectId);
        assertEq(minted, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                AllowanceBasedMinter_ABV2.ArtistAlreadyMinted.selector, 
                projectId
            )
        );
        minter.artistMint(artistAddress, projectId);
        assertEq(main721Contract.balanceOf(artistAddress), 1);

        vm.stopPrank();
    }
    
    // not artist can't mint with artistMint
    function testNotArtistCantMint() public {
        
        uint256 projectId = 0;

        vm.prank(deployer);
        minter.setArtistLimit(projectId, 1);

        (uint256 limit, uint256 minted) = minter.getArtistLimitAndMinted(projectId);
        assertEq(limit, 1);
        assertEq(minted, 0);

        address notArtistAddress = address(0x401a57151);
        assertFalse(artistAddress == notArtistAddress);

        vm.startPrank(notArtistAddress);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                AllowanceBasedMinter_ABV2.NotArtist.selector, 
                notArtistAddress,
                projectId
            )
        );
        minter.artistMint(artistAddress, projectId);
        
        (, minted) = minter.getArtistLimitAndMinted(projectId);
        assertEq(minted, 0);
        
        assertEq(main721Contract.balanceOf(notArtistAddress), 0);

        vm.stopPrank();
    }

    // withdrawal tests
      function testCanWithdraw() public {
        
        uint256 projectId = 0;
        uint256 price = 1e18;

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer, price, projectId);
        vm.prank(customer);
        minter.order{value: price}(customer, nonce, signature);

        assertEq(minter.owner(), deployer);
        uint256 balanceDeployerBefore = deployer.balance;

        assertEq(address(minter).balance, price);

        vm.prank(deployer);
        minter.withdraw(price);

        uint256 balanceDeployerAfter = deployer.balance;

        assertEq(balanceDeployerAfter, balanceDeployerBefore + price);
    }

    function buildAndSign(address _customer, uint256 _price, uint256 _projectId) internal view
        returns (uint256 nonce, bytes memory signature) {
            nonce = (((currentAllowanceId << 64) + _projectId) << 128) + _price;
            bytes32 hashToSign = (minter.createMessage(_customer, nonce)).toEthSignedMessageHash();
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(allowanceSignerPrivateKey , hashToSign);
            signature = abi.encodePacked(r,s,v);
    }

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

}