// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./GameToken.sol";

// ============================================================================
// 5. TOURNAMENT MANAGER CONTRACT
// ============================================================================

contract TournamentManager is Ownable, ReentrancyGuard, Pausable {
    GameToken public gameToken;
    
    struct Tournament {
        uint256 id;
        string name;
        uint256 startTime;
        uint256 endTime;
        uint256 entryFee;
        uint256 prizePool;
        uint256 maxParticipants;
        uint256 participantCount;
        bool isActive;
        mapping(address => bool) participants;
        mapping(address => uint256) scores;
        address[] participantList;
    }
    
    mapping(uint256 => Tournament) public tournaments;
    uint256 public tournamentCounter;
    uint256 public platformFeePercent = 500; // 5%
    
    event TournamentCreated(uint256 id, string name, uint256 startTime, uint256 endTime, uint256 entryFee);
    event TournamentJoined(uint256 tournamentId, address participant);
    event ScoreUpdated(uint256 tournamentId, address participant, uint256 score);
    event TournamentEnded(uint256 tournamentId, address[] winners, uint256[] prizes);
    
    constructor(address _gameToken) {
        gameToken = GameToken(_gameToken);
    }
    
    function createTournament(string memory name, uint256 duration, uint256 entryFee, uint256 maxParticipants) external onlyOwner returns (uint256) {
        tournamentCounter++;
        Tournament storage t = tournaments[tournamentCounter];
        t.id = tournamentCounter;
        t.name = name;
        t.startTime = block.timestamp;
        t.endTime = block.timestamp + duration;
        t.entryFee = entryFee;
        t.maxParticipants = maxParticipants;
        t.isActive = true;
        
        emit TournamentCreated(tournamentCounter, name, t.startTime, t.endTime, entryFee);
        return tournamentCounter;
    }
    
    function joinTournament(uint256 tournamentId) external nonReentrant whenNotPaused {
        Tournament storage t = tournaments[tournamentId];
        require(t.isActive, "Tournament not active");
        require(block.timestamp < t.endTime, "Tournament ended");
        require(!t.participants[msg.sender], "Already joined");
        require(t.participantCount < t.maxParticipants, "Tournament full");
        
        if (t.entryFee > 0) {
            require(gameToken.balanceOf(msg.sender) >= t.entryFee, "Insufficient tokens");
            gameToken.transferFrom(msg.sender, address(this), t.entryFee);
            t.prizePool += t.entryFee;
        }
        
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
        
        // Simplified prize distribution (e.g., winner takes all for this example)
        if (winnerCount > 0 && totalPrizePool > 0) {
            gameToken.transfer(sortedParticipants[0], totalPrizePool);
        }
        
        // A more complex prize distribution logic would be needed for multiple winners
        emit TournamentEnded(tournamentId, sortedParticipants, new uint256[](0));
    }

    function _sortParticipantsByScore(Tournament storage t) private view returns (address[] memory) {
        address[] memory participants = t.participantList;
        // WARNING: Bubble sort is not suitable for production.
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
