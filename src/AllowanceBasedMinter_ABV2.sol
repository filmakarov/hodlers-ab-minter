// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.9;

import {SignedAllowance} from "./SignedAllowance.sol";
import {IGenArt721CoreV2_PBAB} from "@artblocks/interfaces/0.8.x/IGenArt721CoreV2_PBAB.sol";
import {Ownable} from "@openzeppelin/contracts/Access/Ownable.sol";

contract AllowanceBasedMinter_ABV2 is SignedAllowance, Ownable {

    error NotEnoughValueProvided(uint256 expected, uint256 provided);
    error NotArtist(address sender, uint256 projectId);
    error ArtistAlreadyMinted(uint256 projectId);
    error WithdrawFailed();

    IGenArt721CoreV2_PBAB public main721Contract;

    struct ArtistLimit {
        uint256 limit;
        uint256 minted;
    }

    mapping (uint256 => ArtistLimit) private artistLimits;

    uint256 public price;
    uint256 public curProjectId;

    address public abWalletAddress;
    address public hodlersMultisigAddress;

    constructor (address _main721ContractAddress, address _abWalletAddress, address _hodlersMultisigAddress) {
        main721Contract = IGenArt721CoreV2_PBAB(_main721ContractAddress);
        abWalletAddress = _abWalletAddress;
        hodlersMultisigAddress = _hodlersMultisigAddress;
    }

    function order(address to, uint256 nonce, bytes memory signature) public payable {

        if (msg.value < price) revert NotEnoughValueProvided(price, msg.value);
        
        // this will throw if the allowance has already been used or is not valid
        _useAllowance(to, nonce, signature);

        main721Contract.mint(to, curProjectId, msg.sender);

        uint256 tenPercent = price/10;
        (bool successAB, ) = payable(abWalletAddress).call{value: tenPercent}("");
        (bool successH, ) = payable(hodlersMultisigAddress).call{value: (price - tenPercent)}("");
        if (!(successAB && successH)) revert WithdrawFailed();

    }

    function artistMint(address to, uint256 projectId) public {
        if (msg.sender != main721Contract.projectIdToArtistAddress(projectId)) revert NotArtist(msg.sender, projectId);
        if (artistLimits[projectId].minted == artistLimits[projectId].limit) revert ArtistAlreadyMinted(projectId);
        ++artistLimits[projectId].minted;
        main721Contract.mint(to, projectId, msg.sender);
    }

    function setPrice(uint256 _newPrice) public onlyOwner {
        price = _newPrice;
    }

    function setCurProjectId(uint256 _newProjectId) public onlyOwner {
        curProjectId = _newProjectId;
    }

    function setAbWallet(address _abWalletAddress) public onlyOwner {
        abWalletAddress = _abWalletAddress;
    }

    function setHodlersMultisig(address _hodlersMultisig) public onlyOwner {
        hodlersMultisigAddress = _hodlersMultisig;
    }
    
    function setArtistLimit(uint256 projectId, uint256 newLimit) public onlyOwner {
        artistLimits[projectId].limit = newLimit;
    }

    function getArtistLimitAndMinted(uint256 projectId) public view returns (uint256, uint256) {
        return (artistLimits[projectId].limit, artistLimits[projectId].minted);
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
        (bool success, ) = payable(owner()).call{value: amt}("");
        if (!success) revert WithdrawFailed();
    } 

}