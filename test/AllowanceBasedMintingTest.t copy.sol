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
    address abWallet;
    address hodlersMultisig;

    uint256 currentAllowanceId;

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
        

        allowanceSignerPrivateKey = 0x4a5113;
        allowanceSignerAddress = vm.addr(allowanceSignerPrivateKey);
        minter = new AllowanceBasedMinter_ABV2(address(main721Contract), abWallet, hodlersMultisig);
        minter.setAllowancesSigner(allowanceSignerAddress);

        minter.setCurProjectId(startingProjectId);
        minter.setPrice(1e17);
        
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
        uint256 price = minter.price();
        
        (,,,, bool isActive,,,,) = main721Contract.projectTokenInfo(projectId); 
        assertEq(isActive, false);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);

        vm.startPrank(customer);
        vm.expectRevert("Project must exist and be active");
        minter.order{value: price}(customer, nonce, signature);
        vm.stopPrank();
    }

    // can not mint when active but paused
    function testCanNotMintWhenActiveButPaused() public {
        uint256 projectId = 0;
        uint256 price = minter.price();

        vm.prank(managerAddress);
        main721Contract.toggleProjectIsActive(projectId);
        
        (,,,, bool isActive,,,,) = main721Contract.projectTokenInfo(projectId); 
        (,,,, bool isPaused) = main721Contract.projectScriptInfo(projectId);
        assertEq(isActive, true);
        assertEq(isPaused, true);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);

        vm.startPrank(customer);
        vm.expectRevert("Purchases are paused.");
        minter.order{value: price}(customer, nonce, signature);
        vm.stopPrank(); 
    }

    // can mint when everything in order
    function testCanMintAndEthIsDistributed() public {
        
        uint256 projectId = 0;
        uint256 price = minter.price();

        activateProject(projectId);

        assertEq(main721Contract.balanceOf(customer), 0);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        vm.prank(customer);
        minter.order{value: price}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);

        assertEq(abWallet.balance, price/10);
        assertEq(hodlersMultisig.balance, price*9/10);
    }

    function testCanChangePriceAndMint() public {
        
        uint256 projectId = 0;
        uint256 newPrice = minter.price() + 1e17;

        activateProject(projectId);

        vm.prank(deployer);
        minter.setPrice(newPrice);

        assertEq(minter.price(), newPrice);

        assertEq(main721Contract.balanceOf(customer), 0);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        vm.prank(customer);
        minter.order{value: newPrice}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);

        assertEq(abWallet.balance, newPrice/10);
        assertEq(hodlersMultisig.balance, newPrice*9/10);
    }

    // can not mint when wrong value sent
    function testCanNotMintWithWrongValue() public {
        
        uint256 projectId = 0;
        uint256 price = minter.price();

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        
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
        uint256 price = minter.price();

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        
        // make price 1 wei
        uint256 manipulatedNonce = nonce + 1; 
        
        vm.startPrank(customer);
        vm.expectRevert("!INVALID_SIGNATURE!");
        minter.order{value: price}(customer, manipulatedNonce, signature);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(customer), 0);
    }

    // can not mint with other person's signature
    function testCanNotMintWithOtherPersonSignature() public {
        
        uint256 projectId = 0;
        uint256 price = minter.price();

        activateProject(projectId);

        address darkHacker = address(0x7ac1c35);
        vm.deal(darkHacker, 1e20);
        assertFalse(darkHacker == customer);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        
        vm.startPrank(darkHacker);
        vm.expectRevert("!INVALID_SIGNATURE!");
        minter.order{value: price}(darkHacker, nonce, signature);
        vm.stopPrank();

        assertEq(main721Contract.balanceOf(address(darkHacker)), 0);
    }

    // can not reuse signature
    function testCanNotReuseSignature() public {
        
        uint256 projectId = 0;
        uint256 price = minter.price();

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        
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
        uint256 price = minter.price();

        activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        vm.prank(customer);
        minter.order{value: price+111}(customer, nonce, signature);

        assertEq(minter.owner(), deployer);
        uint256 balanceDeployerBefore = deployer.balance;

        uint256 minterExceedBalance = address(minter).balance;
        //console.log(minterExceedBalance);

        vm.prank(deployer);
        minter.withdraw(address(minter).balance);

        uint256 balanceDeployerAfter = deployer.balance;

        assertEq(balanceDeployerAfter, balanceDeployerBefore + minterExceedBalance);
    
    }

    function buildAndSign(address _customer) internal 
        returns (uint256 nonce, bytes memory signature) {
            nonce = currentAllowanceId++;
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