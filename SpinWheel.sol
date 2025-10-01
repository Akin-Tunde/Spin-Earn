// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "./GameToken.sol";
import "./Treasury.sol";


contract SpinWheel is VRFV2PlusWrapperConsumerBase, ConfirmedOwner, ReentrancyGuard, Pausable {
    
    // VRF v2.5 Wrapper and request parameters
    address private constant WRAPPER_ADDRESS = 0xb0407dbe851f8318bd31404A49e658143C982F23; // Sepolia
    address private constant LINK_ADDRESS = 0x88Fb150BDc53A65fe94Dea0c9BA0a6dAf8C6e196; // Sepolia

    uint32 private constant CALLBACK_GAS_LIMIT = 250000;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    GameToken public gameToken;
    Treasury public treasury;

    uint256 public dailyFreeSpins = 3;
    uint256 public premiumSpinCost = 50 * 10**18;
    uint256 public maxDailyPremiumSpins = 20;

    // Jackpot System
    uint256 public jackpotPool;
    uint256 public jackpotContributionPercent = 100;
    uint256 public jackpotSeedAmount;
    uint8 public jackpotTier = 4;

    // RewardTier struct and mapping
    struct RewardItem {
        address tokenAddress;
        uint256 amount;
        uint256 fallbackAmountInGameToken;
    }

    struct RewardTier {
        uint16 probability;
        RewardItem[] rewards;
    }
    RewardTier[5] public rewardTiers;
    
    // UserData and request mappings
    struct UserData {
        uint256 lastSpinDay;
        uint8 dailySpinsUsed;
        uint8 dailyPremiumSpins;
    }
    mapping(address => UserData) public userData;
    mapping(uint256 => address) public spinRequests;
    mapping(uint256 => bool) public isPremiumSpin;
    
    event SpinRequested(address indexed user, uint256 requestId, bool isPremium);
    event SpinResult(address indexed user, uint256 requestId, uint8 tier, bool isPremium);
    event RewardTokenDepleted(address indexed token, address indexed user, uint256 amount);
    event JackpotWon(address indexed winner, uint256 amount);

    constructor(address _gameToken, address payable _treasury) 
        VRFV2PlusWrapperConsumerBase(WRAPPER_ADDRESS)
        ConfirmedOwner(msg.sender)
    {
        gameToken = GameToken(_gameToken);
        treasury = Treasury(_treasury);
        _initializeRewardTiers();
    }
    
    function spin() external nonReentrant whenNotPaused {
        UserData storage user = userData[msg.sender];
        _updateDailyData(msg.sender);
        require(user.dailySpinsUsed < dailyFreeSpins, "Daily free spins used");
        user.dailySpinsUsed++;

        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));
        
       
        (uint256 requestId, ) = requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, NUM_WORDS, extraArgs);
        
        spinRequests[requestId] = msg.sender;
        isPremiumSpin[requestId] = false;
        emit SpinRequested(msg.sender, requestId, false);
    }
    
    function premiumSpin() external payable nonReentrant whenNotPaused {
        UserData storage user = userData[msg.sender];
        _updateDailyData(msg.sender);
        require(user.dailyPremiumSpins < maxDailyPremiumSpins, "Exceeds daily premium limit");
        user.dailyPremiumSpins++;

        uint256 contribution = (premiumSpinCost * jackpotContributionPercent) / 10000;
        uint256 burnAmount = premiumSpinCost - contribution;
        
        if (contribution > 0) {
            gameToken.transferFrom(msg.sender, address(this), contribution);
            jackpotPool += contribution;
        }
        if (burnAmount > 0) {
            gameToken.burnFrom(msg.sender, burnAmount);
        }

        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));

       
        (uint256 requestId, ) = requestRandomnessPayInNative(CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, NUM_WORDS, extraArgs);
        
        spinRequests[requestId] = msg.sender;
        isPremiumSpin[requestId] = true;
        emit SpinRequested(msg.sender, requestId, true);
    }
    
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        address user = spinRequests[_requestId];
        require(user != address(0), "Invalid request");
        
        uint256 randomNumber = _randomWords[0] % 10000;
        uint8 winningTier = _determineWinningTier(randomNumber);
        bool premium = isPremiumSpin[_requestId];
        
        if (winningTier == jackpotTier) {
            uint256 jackpotWinnings = jackpotPool;
            if (jackpotWinnings > 0) {
                jackpotPool = jackpotSeedAmount;
                treasury.distributeReward(user, address(gameToken), jackpotWinnings);
                emit JackpotWon(user, jackpotWinnings);
            }
        }

        RewardTier storage tier = rewardTiers[winningTier];
        for (uint i = 0; i < tier.rewards.length; i++) {
            RewardItem memory item = tier.rewards[i];
            
            uint256 amountToReward = item.amount;
            if (premium) { amountToReward = amountToReward * 120 / 100; }
            
            if (amountToReward > 0) {
                bool success = treasury.distributeReward(user, item.tokenAddress, amountToReward);
                if (!success && item.fallbackAmountInGameToken > 0) {
                    emit RewardTokenDepleted(item.tokenAddress, user, amountToReward);
                    uint256 fallbackAmount = item.fallbackAmountInGameToken;
                    if (premium) { fallbackAmount = fallbackAmount * 120 / 100; }
                    treasury.distributeReward(user, address(gameToken), fallbackAmount);
                }
            }
        }
        
        delete spinRequests[_requestId];
        delete isPremiumSpin[_requestId];
        emit SpinResult(user, _requestId, winningTier, premium);
    }

    function withdrawNative() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
    
    function _initializeRewardTiers() private {
        rewardTiers[0].probability = 7750;
        rewardTiers[0].rewards.push(RewardItem(address(gameToken), 1 * 10**18, 0));
        rewardTiers[1].probability = 1500;
        rewardTiers[1].rewards.push(RewardItem(address(gameToken), 10 * 10**18, 0));
        rewardTiers[2].probability = 500;
        rewardTiers[2].rewards.push(RewardItem(address(gameToken), 25 * 10**18, 0));
        rewardTiers[3].probability = 200;
        rewardTiers[3].rewards.push(RewardItem(address(gameToken), 50 * 10**18, 0));
        rewardTiers[4].probability = 50;
        rewardTiers[4].rewards.push(RewardItem(address(gameToken), 100 * 10**18, 0));
    }
    
    function _determineWinningTier(uint256 randomNumber) private view returns (uint8) {
        uint256 cumulative = 0;
        for (uint8 i = 0; i < rewardTiers.length; i++) {
            cumulative += rewardTiers[i].probability;
            if (randomNumber < cumulative) { return i; }
        }
        return 0;
    }

    function _updateDailyData(address user) private {
        uint256 currentDay = block.timestamp / 86400;
        if (userData[user].lastSpinDay != currentDay) {
            userData[user].lastSpinDay = currentDay;
            userData[user].dailySpinsUsed = 0;
            userData[user].dailyPremiumSpins = 0;
        }
    }

    function setJackpotParameters(uint256 _contributionPercent, uint256 _seedAmount) external onlyOwner {
        require(_contributionPercent <= 1000, "Fee too high");
        jackpotContributionPercent = _contributionPercent;
        jackpotSeedAmount = _seedAmount;
    }
}
