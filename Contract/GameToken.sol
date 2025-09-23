// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ============================================================================
// 1. GAME TOKEN CONTRACT (ERC-20)
// ============================================================================

contract GameToken is ERC20, Ownable {
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    
    uint256 public maxSupply = 1_000_000_000 * 10**18; // 1 Billion tokens
    uint256 public totalBurned;
    
    event MinterAdded(address minter);
    event MinterRemoved(address minter);
    event TokensBurned(address from, uint256 amount);
    
    constructor() ERC20("SpinGame Token", "SPIN") {}
    
    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized to mint");
        _;
    }
    
    modifier onlyBurner() {
        require(burners[msg.sender], "Not authorized to burn");
        _;
    }
    
    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
        emit MinterAdded(_minter);
    }
    
    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
        emit MinterRemoved(_minter);
    }
    
    function addBurner(address _burner) external onlyOwner {
        burners[_burner] = true;
    }
    
    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= maxSupply, "Exceeds max supply");
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        totalBurned += amount;
        emit TokensBurned(msg.sender, amount);
    }
    
    function burnFrom(address from, uint256 amount) external {
        // This allows an approved contract (like SpinWheel) to burn tokens
        if(msg.sender != from && !burners[msg.sender]) {
             _spendAllowance(from, msg.sender, amount);
        } else if (msg.sender != from && burners[msg.sender]) {
            // A burner contract doesn't need allowance
        }
        _burn(from, amount);
        totalBurned += amount;
        emit TokensBurned(from, amount);
    }
}
