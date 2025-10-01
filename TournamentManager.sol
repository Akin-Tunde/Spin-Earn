// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./GameToken.sol";


contract TournamentManager is Ownable, ReentrancyGuard, Pausable {
    GameToken public gameToken;

    // MODIFICATION: Added an enum for fee types
    enum FeeType { FREE, NATIVE_TOKEN, ERC20_TOKEN, ERC721_GATE }

    struct Tournament {
        uint256 id;
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 prizePool;
        uint256 maxParticipants;
        uint256 participantCount;
        bool isActive;
        
        // --- MODIFICATION: Updated fee structure ---
        FeeType feeType;
        address feeTokenAddress; // Address for ERC20 token or ERC721 NFT
        uint256 feeAmount;       // Amount for NATIVE_TOKEN or ERC20_TOKEN
        // --- End of Modification ---

        mapping(address => bool) participants;
        mapping(address => uint256) scores;
        address[] participantList;
    }
    
    mapping(uint256 => Tournament) public tournaments;
    uint256 public tournamentCounter;
    uint256 public platformFeePercent = 500; // 5%
    
    // MODIFICATION: Updated event to include new fee details
    event TournamentCreated(uint256 id, string name, uint256 startTime, uint256 endTime, FeeType feeType, address feeToken, uint256 feeAmount);
    event TournamentJoined(uint256 tournamentId, address participant);
    event ScoreUpdated(uint256 tournamentId, address participant, uint256 score);
    event TournamentEnded(uint256 tournamentId, address[] winners, uint256[] prizes);
    
    constructor(address _gameToken) Ownable(msg.sender) {
        gameToken = GameToken(_gameToken);
    }
    
    /**
     * @dev Pauses the contract, preventing players from joining tournaments.
     * Can only be called by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing players to join tournaments again.
     * Can only be called by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // MODIFICATION: Updated function signature and logic to support flexible fees
    function createTournament(
        string memory name,
        uint256 duration,
        uint256 maxParticipants,
        FeeType _feeType,
        address _feeTokenAddress,
        uint256 _feeAmount
    ) external onlyOwner returns (uint256) {
        // Validation for fee parameters
        if (_feeType == FeeType.ERC20_TOKEN || _feeType == FeeType.ERC721_GATE) {
            require(_feeTokenAddress != address(0), "Fee token/NFT address cannot be zero");
        }
        if (_feeType == FeeType.NATIVE_TOKEN || _feeType == FeeType.ERC20_TOKEN) {
            require(_feeAmount > 0, "Fee amount must be greater than zero");
        }

        tournamentCounter++;
        Tournament storage t = tournaments[tournamentCounter];
        t.id = tournamentCounter;
        t.name = name;
        t.startTime = block.timestamp;
        t.endTime = block.timestamp + duration;
        t.maxParticipants = maxParticipants;
        t.isActive = true;

        // Set the new fee structure
        t.feeType = _feeType;
        t.feeTokenAddress = _feeTokenAddress;
        t.feeAmount = _feeAmount;
        
        emit TournamentCreated(tournamentCounter, name, t.startTime, t.endTime, _feeType, _feeTokenAddress, _feeAmount);
        return tournamentCounter;
    }
    
    function joinTournament(uint256 tournamentId) external nonReentrant whenNotPaused {
        Tournament storage t = tournaments[tournamentId];
        require(t.isActive, "Tournament not active");
        require(block.timestamp < t.endTime, "Tournament ended");
        require(!t.participants[msg.sender], "Already joined");
        require(t.participantCount < t.maxParticipants, "Tournament full");
        
        // --- MODIFICATION: Handle different fee types ---
        if (t.feeType == FeeType.NATIVE_TOKEN) {
            // Pay with the platform's native SPIN token
            require(gameToken.balanceOf(msg.sender) >= t.feeAmount, "Insufficient SPIN tokens");
            gameToken.transferFrom(msg.sender, address(this), t.feeAmount);
            t.prizePool += t.feeAmount;
        } else if (t.feeType == FeeType.ERC20_TOKEN) {
            // Pay with a different specified ERC-20 token
            IERC20 feeToken = IERC20(t.feeTokenAddress);
            require(feeToken.balanceOf(msg.sender) >= t.feeAmount, "Insufficient ERC20 tokens");
            feeToken.transferFrom(msg.sender, address(this), t.feeAmount);
            // Note: Prize pool logic for multi-token would be more complex; for now, we assume it's collected here.
        } else if (t.feeType == FeeType.ERC721_GATE) {
            // Entry requires owning an NFT from a specific collection
            IERC721 nftContract = IERC721(t.feeTokenAddress);
            require(nftContract.balanceOf(msg.sender) > 0, "Required NFT not owned");
        }
        // If FeeType is FREE, no action is taken.
        // --- End of Modification ---

        t.participants[msg.sender] = true;
        t.participantList.push(msg.sender);
        t.participantCount++;
        
        emit TournamentJoined(tournamentId, msg.sender);
    }
    
    function updateScore(uint256 tournamentId, address participant, uint256 score) external onlyOwner {
        Tournament storage t = tournaments[tournamentId];
        require(t.isActive, "Tournament not active");
        require(t.participants[participant], "Not a participant");
        t.scores[participant] = score;
        emit ScoreUpdated(tournamentId, participant, score);
    }
    
    function endTournament(uint256 tournamentId) external onlyOwner {
        Tournament storage t = tournaments[tournamentId];
        require(t.isActive, "Tournament is not active");
        require(block.timestamp >= t.endTime, "Tournament not ended yet");
        
        t.isActive = false;
        
        address[] memory sortedParticipants = _sortParticipantsByScore(t);
        
        uint256 winnerCount = sortedParticipants.length / 10; // Top 10%
        if (winnerCount == 0 && sortedParticipants.length > 0) winnerCount = 1;
        
        uint256 totalPrizePool = (t.prizePool * (10000 - platformFeePercent)) / 10000;
        
        // Simplified prize distribution (assumes prize is in SPIN token)
        if (winnerCount > 0 && totalPrizePool > 0) {
            gameToken.transfer(sortedParticipants[0], totalPrizePool);
        }
        
        emit TournamentEnded(tournamentId, sortedParticipants, new uint256[](0));
    }

    function _sortParticipantsByScore(Tournament storage t) private view returns (address[] memory) {
        address[] memory participants = t.participantList;
        for (uint256 i = 0; i < participants.length; i++) {
            for (uint256 j = i + 1; j < participants.length; j++) {
                if (t.scores[participants[i]] < t.scores[participants[j]]) {
                    (participants[i], participants[j]) = (participants[j], participants[i]);
                }
            }
        }
        return participants;
    }
}
