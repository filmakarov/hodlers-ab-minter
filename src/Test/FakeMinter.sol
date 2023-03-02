// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.8.9;

import {IGenArt721CoreV2_PBAB} from "@artblocks/interfaces/0.8.x/IGenArt721CoreV2_PBAB.sol";

contract FakeMinter {

    IGenArt721CoreV2_PBAB public main721Contract;

    constructor (address _main721ContractAddress) {
        main721Contract = IGenArt721CoreV2_PBAB(_main721ContractAddress);
    }

    function mint(address to, uint256 curProjectId) public {

        main721Contract.mint(to, curProjectId, to);

    }

}