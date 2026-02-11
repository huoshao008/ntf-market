// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/** @title MyNFT
    @dev NFT合约实现，支持铸造，元数据管理和供应量控制
    @notice 使用OpenZeppelin库实现标准ERC721,继承ERC2981接口，实现版税功能
*/
contract MyNET is ERC721,ERC721URIStorage,Ownable,ERC2981 {
    //Token ID计数器
    uint256 private _tokenIdCounter;

    //最大供应量
    uint256 public constant MAX_SUPPLY = 10000;

    //最下铸造价格
    uint256 public minPrice = 0.01 ether;

    //版税接受地址
    address private _royaltReceiver;

    //版税比例（基点，10000 = 100%）
    uint96 private _royaltyBps = 1000;

    /**
     * @dev NFT铸造事件
     * @param minter 铸造者地址
     * @param tokenId  新创建的Token ID
     * @param uri 元数据URI
     */
     event NFTMinted(address indexed minter,uint256 indexed tokenId,string uri);

    /**
     * @dev 构造函数
     * @notice 初始化MFT集合和符号，设置合约所有者
     */
     constructor(address royaltReceiver,uint96 royaltyBps) ERC721("LspNFT","SPNFT") Ownable(msg.sender){
        require(royaltReceiver != address(0),"Invalid royalty receiver");
        require(royaltyBps <= 1000,"Royalty too high");

        _royaltReceiver = royaltReceiver;
        _royaltyBps = royaltyBps;

         // 设置默认版税
        _setDefaultRoyalty(_royaltReceiver, royaltyBps);
     }

    /**
     * @dev 设置版税信息
     * @param receiver 新的版税接收地址
     * @param bps 新的版税比例（基点）
     * @notice 只有合约所有者可以调用
     */
    function setRoyaltyInfo(address receiver, uint96 bps) external onlyOwner {
        require(receiver != address(0), "Invalid receiver");
        require(bps <= 1000, "Royalty too high");
        
        _royaltReceiver = receiver;
        _royaltyBps = bps;
        _setDefaultRoyalty(receiver, bps);
    }

    /**
     * @dev 铸造NFT
     * @param uri NFT的元数据URI（通常是IPFS链接）
     * @return 新创建的Token ID
     * @notice 需要支付mintPrice的ETH才能铸造
     */
     function mint(string memory uri)public payable returns(uint256) {
        //检查供应量
        require(_tokenIdCounter < MAX_SUPPLY,"Max supply reached");

        //检查支付金额
        require(msg.value >= minPrice,"Insufficient payment");

        //地址计数器
        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        //安全铸造NFT
        _safeMint(msg.sender, newTokenId);
        //设置元数据
        _setTokenURI(newTokenId, uri);

        //触发事件
        emit NFTMinted(msg.sender, newTokenId, uri);

        return newTokenId;
     }

    
    /**
     * @dev 查询版税接收地址
     */
     function royaltyReceiver()external view returns(address){
        return _royaltReceiver;
     }

    /**
     * @dev 查询版税比例
     */
    function royaltyBps() external view returns (uint96) {
        return _royaltyBps;
    }

    
    /**
     * @dev 重写tokenURI函数
     * @param tokenId Token ID
     * @return 元数据URI
     * @notice 需要重写以解决多重继承的冲突
     */
    function tokenURI(uint256 tokenId)public view override(ERC721, ERC721URIStorage)returns (string memory){
        return super.tokenURI(tokenId);
     }

    /**
     * @dev 检查接口支持
     * @param interfaceId 接口ID
     * @return 是否支持该接口
     * @notice 支持 ERC165 接口检测
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage,ERC2981) returns (bool) {
       return super.supportsInterface(interfaceId);
    }


    /**
     * @dev 查询供应量
     * @return 已铸造的NFT数量
     */
    function totalSupply()public view returns (uint256){
        return _tokenIdCounter;
    }

    /**
     * @dev 设置铸造价格
     * @param newPrice 新的铸造价格（wei）
     * @notice 只有合约所有者可以调用
     */
     function setMintPrice(uint256 newPrice)public onlyOwner{
        minPrice = newPrice;
    }

     
    /**
     * @dev 提取铸造费用
     */
     function withdraw()public onlyOwner{
        uint256 balance = address(this).balance;
        require(balance > 0,"No balance to withdraw");
        payable(owner()).transfer(balance);
    }

}






