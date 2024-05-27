// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Marketplace1155_2 is Ownable, IERC1155Receiver, ReentrancyGuard {

    address public taxReceiver;     //Address to receive taxes
    IERC20 public tokenSCAR;
    uint256 public taxFees;
    bool public isTax;
    uint256 public deadline;       // Cannot buy token after the deadline
    uint256 public maxList;        // Maximum tokens one address can have on the marketplace 

    struct MarketItem {
        address seller;
        uint256 price;
        uint256 time;
        bool canBid;                // Auction switch
        address highestBidder;      // Highest bidder
        uint256 highestBid;         // Highest bid amount
    }

    mapping(address => mapping (address => uint256)) public counter;
    mapping(address => mapping (uint256 => MarketItem[])) public items;

    event BuyToken(address itemType, uint256 tokenId, uint256 price);
    event SellToken(address itemType, uint256 tokenId, uint256 price, bool canBid);
    event CancelSelling(address itemType, uint256 tokenId);
    event PriceUpdated(address itemType, uint256 tokenId, uint256 price);
    event BidPlaced(address itemType, uint256 tokenId, address bidder, uint256 amount);
    event BidWithdrawn(address itemType, uint256 tokenId, address bidder, uint256 amount);
    event BidRejected(address itemType, uint256 tokenId, address seller, address bidder, uint256 amount);
    event BidAccepted(address itemType, uint256 tokenId, address seller, address bidder, uint256 amount);

    constructor () {
        taxFees= 6;
        isTax= true;
        deadline = 14 days;
        maxList = 12;
        taxReceiver = 0x7a264bD70C24dd1792b2a98e3db69B57060B6b73;
        tokenSCAR = IERC20(0xf4c6a8b0F127c4e03DED1FE3f86795B5d0f4b677);
    }

    // Buy token on the marketplace
    function buyToken(address _itemType, uint256 _tokenId, uint256 _price, uint256 _index) external {
        MarketItem memory listing = items[_itemType][_tokenId][_index];
        require(listing.price == _price, "buyToken: Wrong price");
        require(listing.seller != address(0), "buyToken: Item not listed on the marketplace");
        require(tokenSCAR.balanceOf(msg.sender)>=listing.price, "buyToken: Scar insufficent balance");
        require((block.timestamp-items[_itemType][_tokenId][_index].time) <= deadline);
        require(listing.seller != msg.sender, "buyToken: You cannot buy a item that you listed");

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
        counter[_itemType][items[_itemType][_tokenId][_index].seller]--;
        delete items[_itemType][_tokenId][_index];
        emit BuyToken(_itemType, _tokenId, listing.price);
    }
    
    // List token on the marketplace
    function sellToken(address _itemType, uint256 _tokenId, uint256 _price, bool _canBid) external {
        require(IERC1155(_itemType).balanceOf(msg.sender, _tokenId) >0 , "sellToken: You do not own this token");
        require(_price<tokenSCAR.totalSupply(), "sellToken: Price can not exceed SCAR total supply");
        require(counter[_itemType][msg.sender] <= maxList);

        IERC1155(_itemType).safeTransferFrom(msg.sender, address(this), _tokenId, 1, "0x00");
        items[_itemType][_tokenId].push(MarketItem(msg.sender, _price, block.timestamp, _canBid, address(0), 0));
        counter[_itemType][msg.sender]++;
        emit SellToken(_itemType, _tokenId, _price, _canBid);
    }

    // Update item price on the marketplace
    function updatePrice(address _itemType, uint256 _tokenId, uint256 _price, uint256 _index) external {
        require(_price < tokenSCAR.totalSupply(), "updatePrice: Price can not exceed SCAR total supply");
        require(items[_itemType][_tokenId][_index].seller==msg.sender, "updatePrice: You don't own this nft on the Market");
        items[_itemType][_tokenId][_index].price = _price;
        emit PriceUpdated(_itemType, _tokenId, _price);
    }

    // Cancel listing and remove item from the marketplace
    function cancelSelling(address _itemType, uint256 _tokenId, uint256 _index) external {
        MarketItem memory listing = items[_itemType][_tokenId][_index];
        require(listing.seller==msg.sender, "cancelSelling: You don't own this nft on the Market");
        if (listing.highestBidder != address(0)){
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        IERC1155(_itemType).safeTransferFrom(address(this), msg.sender, _tokenId, 1, "0x00");
        counter[_itemType][msg.sender]--;
        delete items[_itemType][_tokenId][_index];
        emit CancelSelling(_itemType, _tokenId);
    }

    function placeBid(address _itemType, uint256 _tokenId, uint256 bidAmount, uint256 _index) external {
        MarketItem memory listing = items[_itemType][_tokenId][_index];
        require(listing.canBid, "placeBid: You cannot bid on this token");
        require(bidAmount > listing.highestBid, "placeBid: Bid amount must be higher");
        require(listing.seller != msg.sender, "placeBid: You cannot bid on your own listing");
        require(block.timestamp <= items[_itemType][_tokenId][_index].time + deadline, "placeBid: You can bid now, deadline reached");

        if (listing.highestBidder != address(0)) {
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        tokenSCAR.transferFrom(msg.sender, address(this), bidAmount);
        items[_itemType][_tokenId][_index].highestBidder = msg.sender;
        items[_itemType][_tokenId][_index].highestBid = bidAmount;

        emit BidPlaced(_itemType, _tokenId, msg.sender, bidAmount);
    }

    function acceptBid(address _itemType, uint256 _tokenId, uint256 _index) external {
        MarketItem storage listing = items[_itemType][_tokenId][_index];
        require(listing.canBid, "acceptBid: No auction for this token");
        require(listing.highestBidder != address(0), "acceptBid: No bids to accept");
        require(listing.seller == msg.sender, "acceptBid: You are not the owner of this NFT on the marketplace");
        require(block.timestamp <= listing.time + deadline, "acceptBid: You cannot accept a bid now, deadline reached");
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
        delete items[_itemType][_tokenId][_index];
        emit BidAccepted(_itemType, _tokenId, msg.sender, listing.highestBidder, listing.highestBid);
    }

    function rejectBid(address _itemType, uint256 _tokenId, uint256 _index) external {
        MarketItem storage listing = items[_itemType][_tokenId][_index];
        require(listing.canBid, "rejectBid: No auction for this token");
        require(listing.highestBidder != address(0), "rejectBid: No bids to reject");
        require(listing.seller == msg.sender, "rejectBid: You are not the owner of this NFT on the marketplace");
        require(block.timestamp <= listing.time + deadline, "rejectBid: You cannot reject a bid now, deadline reached");

        tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        // Reset the bid information
        items[_itemType][_tokenId][_index].highestBidder = address(0);
        items[_itemType][_tokenId][_index].highestBid = 0;

        emit BidRejected(_itemType, _tokenId, listing.seller, listing.highestBidder, listing.highestBid);
    }

    function withdrawBid(address _itemType, uint256 _tokenId, uint256 _index) external {
        MarketItem storage listing = items[_itemType][_tokenId][_index];
        require(listing.canBid, "withdrawBid: You cannot bid on this token");
        require(listing.highestBidder == msg.sender, "withdrawBid: You are not the highest bidder");
        
        tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        
        items[_itemType][_tokenId][_index].highestBidder = address(0);
        items[_itemType][_tokenId][_index].highestBid = 0;

        emit BidWithdrawn(_itemType, _tokenId, msg.sender, listing.highestBid);
    }
    
    function getMarketItem(address _itemType, uint256 _tokenId) external view returns(MarketItem[] memory) {
        uint256 length = items[_itemType][_tokenId].length;
        MarketItem[] memory listing = new MarketItem[](length);
        for (uint256 i; i <length; i++ ) {
            listing[i] = items[_itemType][_tokenId][i];
        }
        return (listing);
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