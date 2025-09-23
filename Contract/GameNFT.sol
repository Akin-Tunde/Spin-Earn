// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// ============================================================================
// 2. GAME NFT CONTRACT (ERC-721)
// ============================================================================

contract GameNFT is ERC721, ERC721Enumerable, Ownable {
    using Strings for uint256;
    
    mapping(address => bool) public minters;
    mapping(uint256 => uint8) public nftRarity; // 0=Common, 1=Uncommon, 2=Rare, 3=Epic, 4=Legendary
    mapping(uint8 => string) public rarityNames;
    mapping(uint8 => uint256) public rarityCount;
    
    string private _baseTokenURI;
    uint256 private _tokenIdCounter = 1;
    uint256 public maxSupply = 100000;
    
    event NFTMinted(address to, uint256 tokenId, uint8 rarity);
    
    constructor() ERC721("SpinGame NFT", "SPINNFT") {
        rarityNames[0] = "Common";
        rarityNames[1] = "Uncommon";
        rarityNames[2] = "Rare";
        rarityNames[3] = "Epic";
        rarityNames[4] = "Legendary";
    }
    
    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized to mint");
        _;
    }
    
    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }
    
    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
    }
    
    function mint(address to, uint8 rarity) external onlyMinter returns (uint256) {
        require(_tokenIdCounter <= maxSupply, "Max supply reached");
        require(rarity <= 4, "Invalid rarity");
        
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(to, tokenId);
        
        nftRarity[tokenId] = rarity;
        rarityCount[rarity]++;
        
        emit NFTMinted(to, tokenId, rarity);
        return tokenId;
    }
    
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json")) : "";
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
