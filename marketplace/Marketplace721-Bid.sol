// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IDEXRouter {
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external pure returns(uint256[] memory);
}

contract Marketplace721 is Ownable, ReentrancyGuard {

    IDEXRouter public router;
    address public BUSD;
    address public taxReceiver;     //Address to receive taxes
    IERC20 public tokenSCAR;        // Scar token
    uint256 public taxFees;         // Listing fees
    bool public isTax;              // Tax switch
    uint256 public deadline;       // Cannot buy token after the deadline

    struct MarketItem {
        address seller;             // Seller address
        uint256 price;              // Listed price
        uint256 time;               // listing time
        bool canBid;                // Auction switch
        address highestBidder;      // Highest bidder
        uint256 highestBid;         // Highest bid amount
    }

    mapping(address => mapping (address => uint256)) public counter; 
    mapping(address => mapping (uint256 => MarketItem)) public items;

    event BuyToken(address itemType, uint256 tokenId, uint256 price);
    event SellToken(address itemType, uint256 tokenId, uint256 price, bool canBid);
    event CancelSelling(address itemType, uint256 tokenId);
    event PriceUpdated(address itemType, uint256 tokenId, uint256 price);
    event BidPlaced(address itemType, uint256 tokenId, address bidder, uint256 amount);
    event BidAccepted(address itemType, uint256 tokenId, address seller, address bidder,uint256 amount);
    event BidRejected(address itemType, uint256 tokenId, address seller, address bidder, uint256 amount);
    event BidWithdrawn(address itemType, uint256 tokenId, address bidder, uint256 amount);

    constructor () {
        router= IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        BUSD= 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
        taxFees= 6;
        isTax= true;
        deadline = 14 days;
        taxReceiver = 0xBdc994a2CD7a35A075ea2e4942d9CE30Cd6659eF;
        tokenSCAR = IERC20(0x8d9fB713587174Ee97e91866050c383b5cEE6209);
    }

    // Buy token on the marketplace
    function buyToken(address _itemType, uint256 _tokenId, uint256 _price) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(listing.price == _price, "buyToken: Wrong price");
        require(listing.seller != address(0), "buyToken: Item not listed on the marketplace");
        require(listing.seller != msg.sender, "buyToken: You cannot buy a item that you listed");
        require(tokenSCAR.balanceOf(msg.sender)>=listing.price, "buyToken: Your SCAR balance is insufficent");
        require(block.timestamp <= listing.time + deadline, "buyToken: Deadline expired, You cannot buy this NFT now");
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
        IERC721(_itemType).transferFrom(address(this), msg.sender, _tokenId);
        counter[_itemType][items[_itemType][_tokenId].seller]--;
        delete items[_itemType][_tokenId];
        emit BuyToken(_itemType, _tokenId, listing.price);
    }
    
    // List token on the marketplace
    function sellToken(address _itemType, uint256 _tokenId, uint256 _price, bool _canBid) external {
        require(_price<tokenSCAR.totalSupply(), "sellToken: The price cannot exceed SCAR total supply");
        require(IERC721(_itemType).ownerOf(_tokenId)==msg.sender, "sellToken: This is not your NFT");

        IERC721(_itemType).transferFrom(msg.sender, address(this), _tokenId);
        items[_itemType][_tokenId] = MarketItem(msg.sender, _price, block.timestamp, _canBid, address(0), 0);
        counter[_itemType][msg.sender]++;
        emit SellToken(_itemType, _tokenId, _price, _canBid);
    }

    function updatePrice(address _itemType, uint256 _tokenId, uint256 _price) external {
        require(_price < tokenSCAR.totalSupply(), "updatePrice: Price can not exceed SCAR total supply");
        require(items[_itemType][_tokenId].seller==msg.sender, "updatePrice: You don't own this nft in the Market");
        require(block.timestamp <= items[_itemType][_tokenId].time + deadline, "updatePrice: You can bid now, deadline reached");
        items[_itemType][_tokenId].price = _price;
        emit PriceUpdated(_itemType, _tokenId, _price);
    }

    function cancelSelling(address _itemType, uint256 _tokenId) external {
        MarketItem storage listing = items[_itemType][_tokenId];
        require(items[_itemType][_tokenId].seller==msg.sender, "cancelSelling: You don't own this nft in the Market");
        if (listing.highestBidder != address(0)){
            tokenSCAR.transfer(listing.highestBidder, listing.highestBid);
        }
        IERC721(_itemType).transferFrom(address(this), msg.sender, _tokenId);
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
        IERC721(_itemType).transferFrom(address(this), listing.highestBidder, _tokenId);
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

    function getBatchMarketItem(address[] memory _itemType, uint256[] memory _tokenId) external view returns(MarketItem[] memory) {
        require(_itemType.length == _tokenId.length, "getBatchMarketItem: Array lenght mismatch");
        MarketItem[] memory listing = new MarketItem[](_itemType.length);
        for (uint256 i;  i<_itemType.length ; i++) {
            listing[i]=(items[_itemType[i]][_tokenId[i]]);
        }
        return listing;
    }

    function getSCARfromBUSD(uint256 _usd) internal view returns(uint256) {
        if(_usd==0) return 0;
        address[] memory path = new address[](2);
        path[0] = BUSD;
        path[1] = address(tokenSCAR);
        return router.getAmountsOut(_usd, path)[1];
    }
    function getBUSDfromSCAR(uint256 _scar) external view returns(uint256) {
        if(_scar==0) return 0;
        address[] memory path = new address[](2);
        path[0] = address(tokenSCAR);
        path[1] = BUSD;
        return router.getAmountsOut(_scar, path)[1];
    }

    function withdrawNFT(address _itemType, address to, uint256 _tokenId) external onlyOwner {
        IERC721(_itemType).transferFrom(address(this), to, _tokenId);
    }

    function withdrawSCAR(address to, uint256 amount) external onlyOwner {
        tokenSCAR.transfer(to, amount);
    }

    function setToken(IERC20 _token) external onlyOwner {
        tokenSCAR= IERC20(_token);
    }

    function setBUSD(address _busd) external onlyOwner {
        BUSD = _busd;
    }

    function setRouter (address _router) external onlyOwner {
        router = IDEXRouter(_router);
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

}