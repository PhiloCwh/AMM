// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract testToken is ERC20, Ownable {
    constructor() ERC20("fuck", "F") {}

    function mint( uint256 amount) public {
        _mint(msg.sender, amount);
    }
}
