// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "@std/console.sol";
import "@std/Script.sol";

import "../src/AllowanceBasedMinter_AB.sol";

contract DeployALMinter is Script {

    AllowanceBasedMinter_AB ALMinter;

    function run() public {

        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ANVIL");
        //vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();

        address filter = 0x533D79A2669A22BAfeCdf1696aD6E738E4A2e07b;
        address abWalletAddress = 0xfed74f78700bB468e824b6BfE4A2ED305a9D86ba;
        address hodlersMultisigAddress = 0xfed74f78700bB468e824b6BfE4A2ED305a9D86ba;

        ALMinter = new AllowanceBasedMinter_AB(filter, abWalletAddress, hodlersMultisigAddress);

        uint256 startingProjectId = 1;
        ALMinter.setCurProjectId(startingProjectId);
        ALMinter.setPrice(0.1 ether);
        ALMinter.setArtistLimit(startingProjectId, 1);

        address allowancesSigner = 0xfed74f78700bB468e824b6BfE4A2ED305a9D86ba;
        address newOwner = 0xfed74f78700bB468e824b6BfE4A2ED305a9D86ba;

        ALMinter.setAllowancesSigner(allowancesSigner);

        ALMinter.transferOwnership(newOwner);
        
        vm.stopBroadcast();

    }

}