// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
/**
 * @title NFT Marketplace
 * @dev This contract facilitates the listing and sale of ERC721 tokens with added enumerable support.
 */
contract Marketplace {
    /// @notice Represents a listing on the marketplace.
    struct Listing {
        address seller;
        uint128 tokenId;
        uint128 price;
        bool isActive;
    }

    /// @notice Owner of the marketplace.
    address payable public immutable owner;

    /// @notice Commission percentage charged by the marketplace (in basis points, 100 = 1%).
    uint256 public commissionPercent;

    /// @notice Maximum commission percentage allowed (50%).
    uint256 public constant MAX_COMMISSION = 5000;

    /// @dev Stores all listings by their unique ID.
    mapping(uint256 => Listing) public listings;

    /// @dev Maps token IDs to their active listing ID.
    mapping(uint256 => uint256) private tokenToListingId;

    /// @dev Pending withdrawals for sellers and owner.
    mapping(address => uint256) public pendingWithdrawals;

    /// @notice Interface for the ERC721 token contract.
    IERC721 public immutable nftContract;

    /// @notice Interface for enumerable ERC721 functionality.
    IERC721Enumerable public immutable nftEnumerable;

    /// @dev Maps seller addresses to their active listings
    mapping(address => Listing[]) private sellerListings;

    /// @notice Event emitted when a new listing is created.
    event ListingCreated(
        uint256 indexed id,
        address indexed seller,
        uint256 tokenId,
        uint256 price,
        uint256 timestamp
    );

    /// @notice Event emitted when an NFT is purchased.
    event PurchaseCompleted(
        uint256 indexed id,
        address indexed buyer,
        uint256 tokenId,
        uint256 price,
        uint256 timestamp
    );

    /// @notice Event emitted when a listing is cancelled.
    event ListingCancelled(uint256 indexed id, address indexed seller);

    /// @notice Event emitted when the marketplace commission is updated.
    event CommissionUpdated(uint256 newPercent);

    /// @notice Event emitted when funds are withdrawn.
    event FundsWithdrawn(uint256 amount, address indexed recipient);

    /// @dev Modifier to restrict certain actions to the contract owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /**
     * @dev Initializes the marketplace with an ERC721 contract and commission percentage.
     * @param _nftContractAddress Address of the ERC721 token contract.
     * @param _commissionPercent Marketplace commission percentage (in basis points).
     */
    constructor(address _nftContractAddress, uint256 _commissionPercent) {
        require(_nftContractAddress != address(0), "Invalid NFT address");
        require(_commissionPercent <= MAX_COMMISSION, "Commission too high");
        
        owner = payable(msg.sender);
        nftContract = IERC721(_nftContractAddress);
        nftEnumerable = IERC721Enumerable(_nftContractAddress);
        commissionPercent = _commissionPercent;
    }

    /**
     * @notice Creates a listing to sell an NFT.
     * @param _tokenId ID of the token to sell.
     * @param _price Sale price in wei.
     */
    function createListing(uint128 _tokenId, uint128 _price) external {
        require(_price > 0, "Price must be > 0");
        
        address tokenOwner = nftContract.ownerOf(_tokenId);
        require(tokenOwner == msg.sender, "Not token owner");
        
        require(
            nftContract.isApprovedForAll(msg.sender, address(this)) ||
            nftContract.getApproved(_tokenId) == address(this),
            "Not approved"
        );

        require(tokenToListingId[_tokenId] == 0, "Already listed");

        uint256 listingId = uint256(keccak256(abi.encodePacked(
            _tokenId,
            msg.sender,
            block.timestamp
        )));

        listings[listingId] = Listing({
            seller: msg.sender,
            tokenId: _tokenId,
            price: _price,
            isActive: true
        });

        tokenToListingId[_tokenId] = listingId;
        sellerListings[msg.sender].push(listings[listingId]);

        emit ListingCreated(listingId, msg.sender, _tokenId, _price, block.timestamp);
    }

    /**
     * @notice Purchases an NFT from an active listing.
     * @param _listingId ID of the listing to purchase.
     */
    function purchaseListing(uint256 _listingId) external payable{
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy own listing");

        uint256 commissionAmount = (msg.value * commissionPercent) / 10000;
        uint256 sellerAmount = msg.value - commissionAmount;

        require(
            nftContract.ownerOf(listing.tokenId) == listing.seller,
            "Seller no longer owns NFT"
        );
        require(
            nftContract.isApprovedForAll(listing.seller, address(this)) ||
            nftContract.getApproved(listing.tokenId) == address(this),
            "Not approved"
        );

        listing.isActive = false;
        delete tokenToListingId[listing.tokenId];
        pendingWithdrawals[owner] += commissionAmount;
        pendingWithdrawals[listing.seller] += sellerAmount;

        nftContract.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);

        emit PurchaseCompleted(
            _listingId,
            msg.sender,
            listing.tokenId,
            listing.price,
            block.timestamp
        );
    }

    /**
     * @notice Cancels an active listing.
     * @param _listingId ID of the listing to cancel.
     */
    function cancelListing(uint256 _listingId) external {
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");

        listing.isActive = false;
        delete tokenToListingId[listing.tokenId];

        emit ListingCancelled(_listingId, msg.sender);
    }

    /**
     * @notice Updates the marketplace commission percentage.
     * @param _newPercent New commission percentage in basis points.
     */
    function setCommissionPercent(uint256 _newPercent) external onlyOwner {
        require(_newPercent <= MAX_COMMISSION, "Commission too high");
        commissionPercent = _newPercent;
        emit CommissionUpdated(_newPercent);
    }

    /**
     * @notice Withdraws pending funds.
     */
    function withdrawFunds() external onlyOwner {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");
 
        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit FundsWithdrawn(amount, msg.sender);
    }

    /**
     * @notice Returns the token ID owned by `_owner` at a specific `index`.
     * @param _owner Address of the token owner.
     * @param index Index in the owner's token list.
     * @return The token ID at the given index.
     */
    function tokenOfOwnerByIndex(address _owner, uint256 index) 
        external
        view 
        returns (uint256) 
    {
        return nftEnumerable.tokenOfOwnerByIndex(_owner, index);
    }

    /**
     * @notice Checks if a token is currently listed.
     * @param _tokenId The token ID to check.
     * @return bool Whether the token is listed.
     */
    function isTokenListed(uint256 _tokenId) external view returns (bool) {
        uint256 listingId = tokenToListingId[_tokenId];
        return listings[listingId].isActive;
    }

    /**
     * @notice Gets the listing ID for a token if it exists.
     * @param _tokenId The token ID to check.
     * @return The listing ID if the token is listed, 0 otherwise.
     */
    function getListingId(uint256 _tokenId) external view returns (uint256) {
        return tokenToListingId[_tokenId];
    }

    /**
     * @notice Gets all listings for a given seller.
     * @param _seller The address of the seller.
     * @return Array of seller's listings.
     */
    function getListingsBySeller(address _seller) external view returns (Listing[] memory) {
        return sellerListings[_seller];
    }

    /**
     * @notice Allows the contract to receive ETH.
     */
    receive() external payable {}
}