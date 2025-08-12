// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFTMarketplace
 * @dev A decentralized marketplace for buying and selling NFTs
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    // Marketplace fee (2.5%)
    uint256 public marketplaceFee = 250; // 250 basis points = 2.5%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Counter for listing IDs
    uint256 private _listingCounter;
    
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
    }
    
    // Mapping from listing ID to listing details
    mapping(uint256 => Listing) public listings;
    
    // Events
    event ItemListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );
    
    event ItemSold(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );
    
    event ItemCanceled(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller
    );
    
    event PriceUpdated(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 newPrice
    );

    constructor(address initialOwner) Ownable(initialOwner) {}
    
    /**
     * @dev List an NFT for sale on the marketplace
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the NFT
     * @param price Price in Wei to sell the NFT for
     */
    function listItem(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant {
        require(price > 0, "Price must be greater than zero");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "You don't own this NFT");
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved to transfer NFT"
        );
        
        _listingCounter++;
        uint256 listingId = _listingCounter;
        
        listings[listingId] = Listing({
            listingId: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true
        });
        
        emit ItemListed(listingId, nftContract, tokenId, msg.sender, price);
    }
    
    /**
     * @dev Buy an NFT from the marketplace
     * @param listingId ID of the listing to purchase
     */
    function buyItem(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Seller cannot buy their own NFT");
        require(
            IERC721(listing.nftContract).ownerOf(listing.tokenId) == listing.seller,
            "Seller no longer owns the NFT"
        );
        
        listing.active = false;
        
        // Calculate marketplace fee
        uint256 fee = (listing.price * marketplaceFee) / FEE_DENOMINATOR;
        uint256 sellerProceeds = listing.price - fee;
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );
        
        // Transfer payment to seller
        payable(listing.seller).transfer(sellerProceeds);
        
        // Refund excess payment if any
        if (msg.value > listing.price) {
            payable(msg.sender).transfer(msg.value - listing.price);
        }
        
        emit ItemSold(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller,
            msg.sender,
            listing.price
        );
    }
    
    /**
     * @dev Cancel a listing (only seller can cancel)
     * @param listingId ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(listing.seller == msg.sender, "Only seller can cancel listing");
        
        listing.active = false;
        
        emit ItemCanceled(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller
        );
    }
    
    /**
     * @dev Update the price of a listing (only seller can update)
     * @param listingId ID of the listing to update
     * @param newPrice New price in Wei
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external nonReentrant {
        require(newPrice > 0, "Price must be greater than zero");
        
        Listing storage listing = listings[listingId];
        
        require(listing.active, "Listing is not active");
        require(listing.seller == msg.sender, "Only seller can update price");
        require(
            IERC721(listing.nftContract).ownerOf(listing.tokenId) == listing.seller,
            "Seller no longer owns the NFT"
        );
        
        listing.price = newPrice;
        
        emit PriceUpdated(
            listingId,
            listing.nftContract,
            listing.tokenId,
            newPrice
        );
    }
    
    /**
     * @dev Get listing details
     * @param listingId ID of the listing
     * @return Listing struct containing all listing information
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @dev Update marketplace fee (only owner)
     * @param newFee New fee in basis points (100 = 1%)
     */
    function updateMarketplaceFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%"); // Max 10% fee
        marketplaceFee = newFee;
    }
    
    /**
     * @dev Withdraw accumulated marketplace fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }
    
    /**
     * @dev Get current listing counter
     * @return Current number of listings created
     */
    function getCurrentListingId() external view returns (uint256) {
        return _listingCounter;
    }
}
