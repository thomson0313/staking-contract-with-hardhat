//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract MockMint is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000000000 * 10 ** decimals());  // Mint 1,000,000 tokens to msg.sender
    }

    // Function to allow anyone to mint more USDT - not for production use
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}