// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Marketplace1155 is Ownable, IERC1155Receiver, ReentrancyGuard {

    address public taxReceiver;     //Address to receive taxes
    IERC20 public tokenSCAR;
    uint256 public taxFees;
    bool public isTax;
    uint256 public deadline;       // Cannot buy token after the deadline

    struct MarketItem {
        address seller;
        uint256 price;
        uint256 time;
        bool canBid;                
        address highestBidder;      // Highest bidder
        uint256 highestBid;         // Highest bid amount
    }

    mapping(address => mapping (address => uint256)) public counter;
    mapping(address => mapping (uint256 => MarketItem)) public items;

    event CancelSelling(address _itemType, uint256 _tokenId);
    event SellToken(address _itemType, uint256 _tokenId, uint256 price, bool canBid);
    event BuyToken(address _itemType, uint256 _tokenId, uint256 price);
    event PriceUpdated(address _itemType, uint256 _tokenId, uint256 _price);
    event BidPlaced(address itemType, uint256 tokenId, address bidder, uint256 amount);
    event BidWithdrawn(address itemType, uint256 tokenId, address bidder, uint256 amount);
    event BidRejected(address itemType, uint256 tokenId, address seller, address bidder, uint256 amount);
    event BidAccepted(address itemType, uint256 tokenId, address seller, address bidder,uint256 amount);

    constructor () {
        taxFees= 6;
        isTax= true;
        deadline = 14 days;
        taxReceiver = 0xBdc994a2CD7a35A075ea2e4942d9CE30Cd6659eF;
        tokenSCAR = IERC20(0x8d9fB713587174Ee97e91866050c383b5cEE6209);
    }

    function buyToken(address _itemType, uint256 _tokenId, uint256 _price) external {
        MarketItem memory listing = items[_itemType][_tokenId];
        require(listing.price == _price, "buyToken: Wrong price");
        require(listing.seller != address(0), "buyToken: Item not listed on the marketplace");
        require(listing.seller != msg.sender, "buyToken: You cannot buy a item that you listed");
        require(tokenSCAR.balanceOf(msg.sender)>=listing.price, "buyToken: Insufficent balance");
        require((block.timestamp-listing.time) <= deadline, "buyToken: Can not buy at this price");
        if (isTax=true) {
            uint256 amountToTaxReceiver = listing.price*taxFees/100;
            uint256 amountToSeller = listing.price-amountToTaxReceiver;
            tokenSCAR.transferFrom(msg.sender, taxReceiver, amountToTaxReceiver);
            tokenSCAR.transferFrom(msg.sender, listing.seller, amountToSeller);
        }
        else {
            tokenSCAR.transferFrom(msg.sender, taxReceiver, listing.price);
        }
        if (listing.highestBidder != address(0)){
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        IERC1155(_itemType).safeTransferFrom(address(this), msg.sender, _tokenId, 1, "0x00");
        counter[_itemType][items[_itemType][_tokenId].seller]--;
        delete items[_itemType][_tokenId];
        emit BuyToken(_itemType, _tokenId, listing.price);
    }
    
    // List token on the marketplace
    function sellToken(address _itemType, uint256 _tokenId, uint256 _price, bool _canBid) external {
        require(IERC1155(_itemType).balanceOf(msg.sender, _tokenId) >0 , "sellToken: You do not own this token");
        require(_price<tokenSCAR.totalSupply(), "sellToken: The price cannot exceed SCAR total supply");

        IERC1155(_itemType).safeTransferFrom(msg.sender, address(this), _tokenId, 1, "0x00");
        items[_itemType][_tokenId] = MarketItem(msg.sender, _price, block.timestamp, _canBid, address(0), 0);
        counter[_itemType][msg.sender]++;
        emit SellToken(_itemType, _tokenId, _price, _canBid);
    }

    function updatePrice(address _itemType, uint256 _tokenId, uint256 _price) external {
        require(_price < tokenSCAR.totalSupply(), "updatePrice: The price can not exceed SCAR total supply");
        require(items[_itemType][_tokenId].seller==msg.sender, "updatePrice: You don't own this nft on the Market");
        items[_itemType][_tokenId].price = _price;
        emit PriceUpdated(_itemType, _tokenId, _price);
    }

    function cancelSelling(address _itemType, uint256 _tokenId) external {
        MarketItem memory listing = items[_itemType][_tokenId];
        require(listing.seller==msg.sender, "cancelSelling: You don't own this nft on the Market");
        if (listing.highestBidder != address(0)){
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        IERC1155(_itemType).safeTransferFrom(address(this), msg.sender, _tokenId, 1, "0x00");
        counter[_itemType][msg.sender]--;
        delete items[_itemType][_tokenId];
        emit CancelSelling(_itemType, _tokenId);
    }

    function placeBid(address _itemType, uint256 _tokenId, uint256 bidAmount) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(listing.canBid, "placeBid: You cannot bid on this token");
        require(bidAmount > listing.highestBid, "placeBid: Bid amount must be higher");
        require(listing.seller != msg.sender, "placeBid: You cannot bid on your own listing");
        require(block.timestamp <= items[_itemType][_tokenId].time + deadline, "placeBid: You can bid now, deadline reached");

        if (listing.highestBidder != address(0)) {
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        tokenSCAR.transferFrom(msg.sender, address(this), bidAmount);
        items[_itemType][_tokenId].highestBidder = msg.sender;
        items[_itemType][_tokenId].highestBid = bidAmount;

        emit BidPlaced(_itemType, _tokenId, msg.sender, bidAmount);
    }

    function acceptBid(address _itemType, uint256 _tokenId) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(listing.canBid, "acceptBid: You cannot bid on this token");
        require(listing.highestBidder != address(0), "acceptBid: No bids to accept");
        require(listing.seller == msg.sender, "acceptBid: You afre not the owner of this NFT on the marketplace");
        require(block.timestamp <= items[_itemType][_tokenId].time + deadline, "acceptBid: You can bid now, deadline reached");
        
        IERC1155(_itemType).safeTransferFrom(address(this), listing.highestBidder, _tokenId, 1, "0x00");
        if (isTax=true) {
            uint256 amountToTaxReceiver = listing.highestBid*taxFees/100;
            uint256 amountToSeller = listing.highestBid-amountToTaxReceiver;
            tokenSCAR.transfer(taxReceiver, amountToTaxReceiver);
            tokenSCAR.transfer(msg.sender, amountToSeller);
        }
        else {
            tokenSCAR.transfer(msg.sender, listing.highestBid);
        }
        counter[_itemType][msg.sender]--;
        delete items[_itemType][_tokenId];
        emit BidAccepted(_itemType, _tokenId, msg.sender, listing.highestBidder, listing.highestBid);
    }

    function rejectBid(address _itemType, uint256 _tokenId) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(listing.canBid, "rejectBid: You cannot bid on this token");
        require(listing.highestBidder != address(0), "rejectBid: No bids to reject");
        require(listing.seller == msg.sender, "rejectBid: You afre not the owner of this NFT on the marketplace");
        require(block.timestamp <= items[_itemType][_tokenId].time + deadline, "rejectBid: You can bid now, deadline reached");

        tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        // Reset the bid information
        items[_itemType][_tokenId].highestBidder = address(0);
        items[_itemType][_tokenId].highestBid = 0;

        emit BidRejected(_itemType, _tokenId, listing.seller, listing.highestBidder, listing.highestBid);
    }

    function withdrawBid(address _itemType, uint256 _tokenId) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(listing.canBid, "withdrawBid: You cannot bid on this token");
        require(listing.highestBidder == msg.sender, "withdrawBid: You are not the highest bidder");
        
        tokenSCAR.transfer(listing.highestBidder, listing.highestBid);

        items[_itemType][_tokenId].highestBidder = address(0);
        items[_itemType][_tokenId].highestBid = 0;

        emit BidWithdrawn(_itemType, _tokenId, msg.sender, listing.highestBid);
    }
    
    function getMarketItem(address _itemType, uint256 _tokenId) external view returns(MarketItem memory) {
        MarketItem memory listing = items[_itemType][_tokenId];
        return listing;
    }

    function withdrawNFT(address _itemType, address to, uint256 _tokenId, uint256 amount) external onlyOwner {
        IERC1155(_itemType).safeTransferFrom(address(this), to, _tokenId, amount, "0x00" );
    }

    function withdrawSCAR(address to, uint256 amount) external onlyOwner {
        tokenSCAR.transfer(to, amount);
    }

    function setToken(IERC20 _token) external onlyOwner {
        tokenSCAR= IERC20(_token);
    }

    function setIsTax(bool _on) external onlyOwner {
        isTax= _on;
    }

    function setTaxFees(uint256 _taxFees) external onlyOwner {
        taxFees= _taxFees;
    }

    function setTaxReceiver(address _taxReceiver) external onlyOwner {
        taxReceiver= _taxReceiver;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external pure override returns (bytes4) {
      //require(from == address(0x0), "Cannot Receive NFTs Directly");
      return IERC1155Receiver.onERC1155Received.selector;
    }
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure override returns (bytes4) {
      //require(from == address(0x0), "Cannot Receive NFTs Directly");
      return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
    return  interfaceID == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceID == 0x4e2312e0;      // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }
}