// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ============================================================================
// 4. TREASURY CONTRACT (Reward Pool Management)
// ============================================================================

contract Treasury is Ownable, ReentrancyGuard {
    address public spinWheelAddress;

    event FundsDeposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawal(address indexed token, address indexed to, uint256 amount);

    modifier onlySpinWheel() {
        require(msg.sender == spinWheelAddress, "Caller is not the SpinWheel contract");
        _;
    }

    function setSpinWheelAddress(address _spinWheelAddress) external onlyOwner {
        spinWheelAddress = _spinWheelAddress;
    }

    function distributeReward(address to, address token, uint256 amount) external onlySpinWheel returns (bool) {
        if (token == address(0) || IERC20(token).balanceOf(address(this)) < amount) {
            return false; // Not enough funds or invalid token, return failure
        }
        return IERC20(token).transfer(to, amount);
    }
    
    function depositTokens(address token, uint256 amount) external {
        require(token != address(0), "Invalid token address");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit FundsDeposited(token, msg.sender, amount);
    }
    
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(amount <= balance, "Amount exceeds balance");
        IERC20(token).transfer(to, amount);
        emit Withdrawal(token, to, amount);
    }

    receive() external payable {
        emit FundsDeposited(address(0), msg.sender, msg.value);
    }
}
