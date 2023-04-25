// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity ^0.8.9;

import {SignedAllowance} from "./SignedAllowance.sol";
import {Ownable} from "@openzeppelin/contracts/Access/Ownable.sol";

interface IFilter {
    function mint(address to, uint256 projectId, address from) external;
    function genArt721CoreAddress() external returns (address);
}

interface IAB721Contract {
    function projectIdToArtistAddress(uint256 projectId) external returns (address);
}

contract AllowanceBasedMinter_AB is SignedAllowance, Ownable {

    error NotEnoughValueProvided(uint256 expected, uint256 provided);
    error NotArtist(address sender, uint256 projectId);
    error ArtistAlreadyMinted(uint256 projectId);
    error WithdrawFailed();

    string public constant minterType = "AllowanceBasedMinter_AB";

    IFilter public filterContract;

    struct ArtistLimit {
        uint256 limit;
        uint256 minted;
    }

    mapping (uint256 => ArtistLimit) private artistLimits;

    uint256 public price;
    uint256 public curProjectId;

    address public abWalletAddress;
    address public hodlersMultisigAddress;

    constructor (address _filterContractAddress, address _abWalletAddress, address _hodlersMultisigAddress) {
        filterContract = IFilter(_filterContractAddress);
        abWalletAddress = _abWalletAddress;
        hodlersMultisigAddress = _hodlersMultisigAddress;
    }

    // we do not introduce reentrancy guard to make mints cheaper, since the only address 
    // that can in theory exploit re-entrancy here is abWalletAddress, which we trust is safe
    function order(address to, uint256 nonce, bytes memory signature) public payable {

        if (msg.value < price) revert NotEnoughValueProvided(price, msg.value);
        
        // this will throw if the allowance has already been used or is not valid
        _useAllowance(to, nonce, signature);

        filterContract.mint(to, curProjectId, msg.sender);

        uint256 tenPercent = price/10;
        (bool successAB, ) = payable(abWalletAddress).call{value: tenPercent}("");
        (bool successH, ) = payable(hodlersMultisigAddress).call{value: (price - tenPercent)}("");
        if (!(successAB && successH)) revert WithdrawFailed();

    }

    function artistMint(address to, uint256 projectId) public {
        IAB721Contract abContract = IAB721Contract(filterContract.genArt721CoreAddress());
        if (msg.sender != abContract.projectIdToArtistAddress(projectId)) revert NotArtist(msg.sender, projectId);
        if (artistLimits[projectId].minted == artistLimits[projectId].limit) revert ArtistAlreadyMinted(projectId);
        ++artistLimits[projectId].minted;
        filterContract.mint(to, projectId, msg.sender);
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
    /// @param _newfilterContractAddress the new main 721 contract address
    function setfilterContract (address _newfilterContractAddress) public onlyOwner {
        filterContract = IFilter(_newfilterContractAddress);
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