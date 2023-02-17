// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.9;

import {SignedAllowance} from "./SignedAllowance.sol";
import {IGenArt721CoreV2_PBAB} from "@artblocks/interfaces/0.8.x/IGenArt721CoreV2_PBAB.sol";
import {Ownable} from "@openzeppelin/contracts/Access/Ownable.sol";

contract AllowanceBasedMinter_ABV2 is SignedAllowance, Ownable {

    error NotEnoughValueProvided(uint256 expected, uint256 provided);
    error NotArtist(address sender, uint256 projectId);
    error ArtistAlreadyMinted(uint256 projectId);

    IGenArt721CoreV2_PBAB public main721Contract;

    struct ArtistLimit {
        uint256 limit;
        uint256 minted;
    }

    mapping (uint256 => ArtistLimit) artistLimits;

    constructor (address _main721ContractAddress) {
        main721Contract = IGenArt721CoreV2_PBAB(_main721ContractAddress);
    }

    function order(address to, uint256 nonce, bytes memory signature) public payable {

        //price is stored in the right-most 128 bits of the nonce
        uint256 price = (nonce << 128) >> 128;

        //projectId is stored in the middle 64 bytes
        uint256 projectId = ((nonce >> 128) << 192) >>192;

        if (msg.value < price) revert NotEnoughValueProvided(price, msg.value);
        
        // this will throw if the allowance has already been used or is not valid
        _useAllowance(to, nonce, signature);

        main721Contract.mint(to, projectId, msg.sender);
    }

    function artistMint(address to, uint256 projectId) public {
        if (msg.sender != main721Contract.projectIdToArtistAddress(projectId)) revert NotArtist(msg.sender, projectId);
        if (artistLimits[projectId].minted == artistLimits[projectId].limit) revert ArtistAlreadyMinted(projectId);
        ++artistLimits[projectId].minted;
        main721Contract.mint(to, projectId, msg.sender);
    }
    
    function setArtistLimit(uint256 projectId, uint256 _newLimit) public onlyOwner {
        artistLimits[projectId].limit = _newLimit;
    }

    /// @notice sets main 721 contract to mint from
    /// @param _newMain721ContractAddress the new main 721 contract address
    function setMain721Contract (address _newMain721ContractAddress) public onlyOwner {
        main721Contract = IGenArt721CoreV2_PBAB(_newMain721ContractAddress);
    }

    /// @notice sets allowance signer, this can be used to revoke all unused allowances already out there
    /// @param _newSigner the new signer
    function setAllowancesSigner(address _newSigner) external onlyOwner {
        _setAllowancesSigner(_newSigner);
    }

    /// @notice Withdraws funds from the contract to msg.sender who is always the owner.
    /// No need to use reentrancy guard as receiver is always owner
    /// @param amt amount to withdraw in wei
    function withdraw(uint256 amt) public onlyOwner {
         address payable beneficiary = payable(owner());
        (bool success, ) = beneficiary.call{value: amt}("");
        if (!success) revert ("Withdrawal failed");
    } 

}