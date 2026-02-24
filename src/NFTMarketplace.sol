// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


/**
 * @title IERC2981
 * @dev ERC2981版税标准接口
 */
interface IERC2981 is IERC165 {
    function royaltyInfo(uint256 tokenId,uint256 salePrice)external view returns(
        address receiver,
        uint256 royaltyAmount
    );
}

/**
 * @title NFTMarketplace
 * @dev 完整的NFT交易市场合约，支持上架、购买、版税和拍卖功能
 * @notice 使用ReentrancyGuard防止重入攻击
 */
contract NFTMarketplace is ReentrancyGuard{
   /**
    *@dev 挂单结构体
    */
     struct Listing{
        //卖家地址
        address seller;
        //NFT合约地址
        address nftContract;
        //Token ID
        uint256 tokenId;
        //售价（wei）
        uint256 price;
        //是否激活
        bool active;
     }

   /**
    *@dev 拍卖结构体
    */
    struct Auction{
        //卖家地址
        address seller;
        //nft合约地址
        address nftContract;
        //Token ID
        uint256 tokenId;
        //起拍价
        uint256 startPrice;
        //展示
        uint256 startPriceValue;
        //当前最高出价
        uint256 highestBid;
        //展示
        uint256 highestBidValue;
        //当前最高出价者
        address highestBidder;
        //拍卖结束时间
        uint256 endTime;
        //是否激活
        bool active;
        // 参与竞价的资产类型 0x 地址表示eth，其他地址表示erc20
        // 0x0000000000000000000000000000000000000000 表示eth
        address tokenAddress;
    }

    //挂单映射
    mapping(uint256 => Listing) public listings;
    uint256 public listingCounter;

    //拍卖映射
    mapping (uint256 => Auction) public auctions;
    uint256 public auctionCounter;

    //待退款映射（拍卖）
    mapping (uint256 => mapping(address => uint256)) public pendingReturns;

    //平台手续费（基点，10000=100%）
    uint256 public platformFee = 250;

    //手续费接受地址
    address public feeRecipient;
    
    //喂价地址（根据资产类型查询地址）
    mapping(address => AggregatorV3Interface) public priceFeeds;

    /**
     * @dev NFT上架事件
     */
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );

    /**
    * @dev NFT下架事件
    */
    event NFTDelisted(
        uint256 indexed listingId
    );

    /**
     * @dev 价格更新事件
     */
    event PriceUpdated(
        uint256 indexed listingId,
        uint256 newPrice
    );

    /**
     * @dev NFT售出事件
     */
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint price
    );

    /**
     * @dev 拍卖创建事件
     */
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 startprice,
        uint256 endTime
    );

    /**
     * @dev 出价事件
     */
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    /**
     * @dev 拍卖结束事件
     */
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 finaPrice
    );

    /**
     * @dev 构造函数
     * @param _feeRecipient 手续费接收地址
     */
    constructor(address _feeRecipient){
        require(_feeRecipient != address(0),"Invalid fee recipient");
        feeRecipient = _feeRecipient;
        priceFeeds[0x0000000000000000000000000000000000000000] = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
    }

    function setPriceFeed(
        address tokenAddress,
        address _priceFeed
    ) public {
        priceFeeds[tokenAddress] = AggregatorV3Interface(_priceFeed);
    }


     // ETH -> USD => 1766 7512 1800 => 1766.75121800
    // USDC -> USD => 9999 4000 => 0.99994000
    function getChainlinkDataFeedLatestAnswer(
        address tokenAddress
    ) public view returns (int) {
        AggregatorV3Interface priceFeed = priceFeeds[tokenAddress];
        // prettier-ignore
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return answer / (10 ** 8);
    }


    /**
     * @dev 上架NFT
     * @param nftContract NFT合约地址
     * @param tokenId Token ID
     * @param price 售价（wei）
     * @return listingId 挂单ID
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    )external returns(uint256){
        require(price > 0,"price must be greater than 0");
        require(nftContract != address(0),"Invalid NFT contract");

        IERC721 nft = IERC721(nftContract);

        //验证所有权
        require(nft.ownerOf(tokenId) == msg.sender,"Not the owner");

        //验证授权
        require(
            nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),"Maketplace not approved"
        );

        //创建挂单
        listingCounter++;
        listings[listingCounter] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit NFTListed(listingCounter,msg.sender,nftContract,tokenId,price);

        return listingCounter;
    }

    /**
     * @dev 下架NFT
     * @param listingId 挂单ID
     */
    function delist(uint256 listingId)external {
        Listing storage listing = listings[listingId];

        require(listing.active,"Listing not active");
        require(listing.seller == msg.sender,"Not the seller");

        listing.active = false;

        emit NFTDelisted(listingId);
    }

    /**
     * @dev 更新挂单价格
     * @param listingId 挂单ID
     * @param newPrice 新价格（wei）
     */
    function updatePrice(uint256 listingId,uint256 newPrice)external{
        require(newPrice > 0,"Price must be greater than 0");

        Listing storage listing = listings[listingId];
        require(listing.active,"Listing not active");
        require(listing.seller == msg.sender,"Not the seller");

        listing.price = newPrice;

        emit PriceUpdated(listingId,newPrice);
    }


    /**
     * @dev 购买NFT
     * @param listingId 挂单ID
     * @notice 需要支付足够的ETH，多余部分会自动退还
     */
    function buyNFT(uint256 listingId)external payable nonReentrant  {
        Listing storage listing = listings[listingId];
        
        //检查挂单状态
        require(listing.active,"Listing not active");
        require(msg.sender != listing.seller,"Cannot buy your own NFT");
        require(msg.value >= listing.price,"Insufficient payment");

        //先更新状态
        listing.active = false;

        //计算手续费
        uint256 fee = (listing.price * platformFee) / 10000;

        //获取办税信息
        (address royaltyReceiver,uint256 royaltyAmount) = _getRoyaltyInfo(
            listing.nftContract,
            listing.tokenId,
            listing.price
        );

        //计算卖家收益
        uint256 sellerAmount = listing.price - fee - royaltyAmount;

        //转移NFT
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        //资金分配：版税->平台手续费->卖家收益
        if(royaltyAmount > 0 && royaltyReceiver != address(0)){
            (bool successRoyalty,) = royaltyReceiver.call{value: royaltyAmount}("");
            require(successRoyalty,"Royalty transfer failed");
        }

        (bool successFee,) = feeRecipient.call{value: fee}("");    
        require(successFee,"Transfer fee failed");

        (bool successSeller,) = listing.seller.call{value: sellerAmount}("");
        require(successSeller,"Tranfer to seller failed");

        //退还多余资金
        if(msg.value > listing.price){
            (bool successRefound,) = msg.sender.call{value: msg.value-listing.price}("");
            require(successRefound,"Refund failed");
        }

        emit NFTSold(listingId,msg.sender,listing.seller,listing.price);
    }

     /**
     * @dev 创建拍卖
     * @param nftContract NFT合约地址
     * @param tokenId Token ID
     * @param startPrice 起拍价（wei）
     * @param durationHours 拍卖时长（小时）
     * @return auctionId 拍卖ID
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 durationHours
    ) external returns(uint256){
        require(startPrice > 0,"Start price must be greater than 0");
        require(durationHours > 1,"Duration must be at least 1 hour");
        require(nftContract != address(0),"Invalid NFT contract");

        IERC721 nft = IERC721(nftContract);

        //验证所有权
        require(nft.ownerOf(tokenId) == msg.sender,"Not the owner");

        //验证授权
        require(
            nft.getApproved(tokenId) == address(this)||
            nft.isApprovedForAll(msg.sender,address(this)),
            "Marketplace not approved"
        );

        //创建拍卖
        auctionCounter++;
        auctions[auctionCounter] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPrice: startPrice,
            startPriceValue: 0,
            highestBid: 0,
            highestBidValue: 0,
            highestBidder: address(0),
            endTime: block.timestamp + (durationHours * 1 hours),
            active: true,
            tokenAddress: 0x0000000000000000000000000000000000000000
        });
        
        emit AuctionCreated(
            auctionCounter,
            msg.sender,
            nftContract,
            tokenId,
            startPrice,
            auctions[auctionCounter].endTime
        );

        return auctionCounter;

    }

    /**
     * @dev 出价
     * @param auctionId 拍卖ID
     * @notice 需要支付足够的ETH，出价必须高于当前最高出价的5%
     */
    function placebid(uint256 auctionId)external payable {
        Auction storage auction = auctions[auctionId];

        require(auction.active,"Auction not active");
        require(block.timestamp < auction.endTime,"Auction ended");
        require(msg.sender != auction.seller,"Seller cannot bid");

        //计算最低出价
        uint256 minBid;
        if(auction.highestBid == 0){
            minBid = auction.startPrice;
        }else{
            //当前增加5%
            minBid = auction.highestBid + (auction.highestBid * 5 / 100);
        }

        require(msg.value >= minBid,"Bid too low");

        // 如果有之前的出价者，记录他们的待退款金额
        if(auction.highestBidder != address(0)){
            pendingReturns[auctionId][auction.highestBidder] += auction.highestBid;
        }

        //更新最高出价
        auction.highestBid = msg.value;
        auction.highestBidValue = auction.highestBid * uint256(getChainlinkDataFeedLatestAnswer(auction.tokenAddress));
        auction.highestBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

     /**
     * @dev 提取出价退款
     * @param auctionId 拍卖ID
     * @notice 被超越的出价者可以提取他们的资金
     */
    function withdrawBid(uint256 auctionId)external{
        uint256 amount = pendingReturns[auctionId][msg.sender];
        require(amount > 0,"No pending return");

        pendingReturns[auctionId][msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success,"Transfer failed");
    }


    /**
     * @dev 结束拍卖
     * @param auctionId 拍卖ID
     * @notice 任何人都可以在拍卖结束后调用此函数进行结算
     */
    function endAuction(uint256 auctionId)external nonReentrant{
        Auction storage auction = auctions[auctionId];

        require(auction.active,"Auction not active");
        require(block.timestamp >= auction.endTime,"Auction not ended");

        auction.active = false;

        if(auction.highestBidder != address(0)){
            //有人出价
            uint256 fee = (auction.highestBid * platformFee) / 10000;

            (address royaltyReceiver,uint256 royaltyAmount) = _getRoyaltyInfo(
                auction.nftContract,
                auction.tokenId,
                auction.highestBid
            );

            uint256 sellerAmount = auction.highestBid -fee - royaltyAmount;

            // 转移NFT
            IERC721(auction.nftContract).safeTransferFrom(
                auction.seller,
                auction.highestBidder,
                auction.tokenId
            );


            // 资金分配
            if(royaltyAmount > 0 && royaltyReceiver != address(0)){
                (bool  successRoyalty,) = royaltyReceiver.call{value: royaltyAmount}("");
                require(successRoyalty,"Royalty transfer failed");
            }

            (bool successFee,) = feeRecipient.call{value: fee}("");
            require(successFee,"Transfer fee failed");

            (bool successSeller,) = auction.seller.call{value: sellerAmount}("");
            require(successSeller,"Transfer to seller failed");

            emit AuctionEnded(
                auctionId,
                auction.highestBidder,
                auction.highestBid
            );
        }else{
            //没有人出价，拍卖流派
            emit AuctionEnded(auctionId,address(0),0);
        }
    }
    




     /**
     * @dev 获取版税信息
     * @param nftContract NFT合约地址
     * @param tokenId Token ID
     * @param salePrice 售价
     * @return receiver 版税接收地址
     * @return royaltyAmount 版税金额
     * @notice 内部函数，检查NFT合约是否支持ERC2981标准
     */
     function _getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
     )internal view returns(address receiver,uint256 royaltyAmount){
        // 检查NFT合约是否支持ERC2981
        if(IERC165(nftContract).supportsInterface(type(IERC2981).interfaceId)){
          (receiver,royaltyAmount)  = IERC2981(nftContract).royaltyInfo(tokenId,salePrice);
        }else{
            //
            receiver = address(0);
            royaltyAmount = 0;
        }
     }

    /**
     * @dev 查询挂单信息
     * @param listingId 挂单ID
     * @return seller 卖家地址
     * @return nftContract NFT合约地址
     * @return tokenId Token ID
     * @return price 价格
     * @return active 是否激活
     */
    function getListing(uint256 listingId)external view returns(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool active
    ){
        Listing memory listing = listings[listingId];
        return (
            listing.seller,
            listing.nftContract,
            listing.tokenId,
            listing.price,
            listing.active
        );
    }
    
    /**
     * @dev 查询拍卖信息
     * @param auctionId 拍卖ID
     * @return seller 卖家地址
     * @return nftContract NFT合约地址
     * @return tokenId Token ID
     * @return startPrice 起拍价
     * @return highestBid 当前最高出价
     * @return highestBidder 当前最高出价者
     * @return endTime 结束时间
     * @return active 是否激活
     */
    function getAuction(uint256 auctionId)external view returns(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 highestBid,
        address highestBidder,
        uint256 endTime,
        bool active
    ){
        Auction memory auction = auctions[auctionId];
        return(
            auction.seller,
            auction.nftContract,
            auction.tokenId,
            auction.startPrice,
            auction.highestBid,
            auction.highestBidder,
            auction.endTime,
            auction.active
        );
    }
    
    /**
     * @dev 设置平台手续费
     * @param newFee 新的手续费（基点）
     * @notice 只有手续费接收地址可以调用
     */
    function setPlatformFee(uint256 newFee)external {
        require(msg.sender == feeRecipient,"Not fee recipient");
        require(newFee <= 1000,"Fee to high");
        platformFee = newFee;
    }

    /**
     * @dev 更新手续费接收地址
     * @param newRecipient 新的接收地址
     * @notice 只有当前手续费接收地址可以调用
     */
     function updateFeeRecipient(address newRecipient)external{
        require(msg.sender == feeRecipient,"Not fee recipient");
        require(newRecipient != address(0),"Invalid address");

        feeRecipient = newRecipient;
     }

}