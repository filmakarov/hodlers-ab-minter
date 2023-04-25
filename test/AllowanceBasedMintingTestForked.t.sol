// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {BasicRandomizer} from "@artblocks/BasicRandomizer.sol";
import {GenArt721CoreV2_PBAB} from "@artblocks/engine/GenArt721CoreV2_PBAB.sol";
import "../src/AllowanceBasedMinter_AB.sol";
import "@std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is default deployer 
 */

interface IFilterExtended is IFilter {
    function addApprovedMinter(address _minterAddress) external;
    function getMinterForProject(uint256 _projectId) external view returns (address);
    function isApprovedMinter(address _minterAddress) external view returns (bool);
    function setMinterForProject(uint256 _projectId, address _minterAddress) external;
}

contract AllowanceBasedMintingTestForked is Test {

    using ECDSA for bytes32;
    
    BasicRandomizer randomizer;
    IFilterExtended filter;
    AllowanceBasedMinter_AB minter;
    IERC721 main721Contract;

    uint256 allowanceSignerPrivateKey;
    address allowanceSignerAddress;

    address artistAddress;
    address managerAddress;
    address customer;

    address deployer;
    address abWallet;
    address hodlersMultisig;

    uint256 currentAllowanceId;

    uint256 goerliFork;

    function setUp() public {

        goerliFork = vm.createFork("https://rpc.ankr.com/eth_goerli");
        vm.selectFork(goerliFork);

        deployer = address(0xde9104e5);
        vm.deal(deployer, 1e21);

        abWallet = address(0xa121b10c5);
        hodlersMultisig = address(0x60d1e125);

        filter = IFilterExtended(0x533D79A2669A22BAfeCdf1696aD6E738E4A2e07b);
        main721Contract = IERC721(0x41cc069871054C1EfB4Aa40aF12f673eA2b6a1fC);

        // Deploy contracts
        vm.startPrank(deployer);

        allowanceSignerPrivateKey = 0x4a5113;
        allowanceSignerAddress = vm.addr(allowanceSignerPrivateKey);
        minter = new AllowanceBasedMinter_AB(address(filter), abWallet, hodlersMultisig);
        minter.setAllowancesSigner(allowanceSignerAddress);

        uint256 startingProjectId = 1;
        minter.setCurProjectId(startingProjectId);
        minter.setPrice(1e17);

        vm.stopPrank();

        vm.startPrank(0x8cc0019C16bced6891a96d32FF36FeAB4A663a40); //admin
        filter.addApprovedMinter(address(minter));
        filter.setMinterForProject(startingProjectId, address(minter));
        vm.stopPrank();

        customer = address(0xdecaf);
        vm.deal(customer, 100*1e18);

        vm.roll(100);
        currentAllowanceId = (block.timestamp + block.number) % 1000;

        artistAddress = 0xe18Fc96ba325Ef22746aDA9A82d521845a2c16f8;
    }

    function testSetupSuccessful() public {
        assertEq(filter.getMinterForProject(1), address(minter));
        assertEq(filter.isApprovedMinter(address(minter)), true);
    }


    // can mint when everything in order
    function testCanMintAndEthIsDistributed() public {
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

        assertEq(main721Contract.balanceOf(customer), 0);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        vm.prank(customer);
        minter.order{value: price}(customer, nonce, signature);

        assertEq(main721Contract.balanceOf(customer), 1);

        assertEq(abWallet.balance, price/10);
        assertEq(hodlersMultisig.balance, price*9/10);
    }


    function testCanChangePriceAndMint() public {
        
        uint256 projectId = 1;
        uint256 newPrice = minter.price() + 1e17;

        //activateProject(projectId);

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
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

        (uint256 nonce, bytes memory signature) = buildAndSign(customer);
        
        uint256 wrongValue = price/2;
        
        vm.startPrank(customer);
        vm.expectRevert(
            abi.encodeWithSelector(
                AllowanceBasedMinter_AB.NotEnoughValueProvided.selector, 
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
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

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
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

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
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

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
        
        uint256 projectId = 1;

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
                AllowanceBasedMinter_AB.ArtistAlreadyMinted.selector, 
                projectId
            )
        );
        minter.artistMint(artistAddress, projectId);
        assertEq(main721Contract.balanceOf(artistAddress), 1);

        vm.stopPrank();
    }
    
    // not artist can't mint with artistMint
    function testNotArtistCantMint() public {
        
        uint256 projectId = 1;

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
                AllowanceBasedMinter_AB.NotArtist.selector, 
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
        
        uint256 projectId = 1;
        uint256 price = minter.price();

        //activateProject(projectId);

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

   

    /*
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
    */

}