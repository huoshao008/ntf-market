// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/NFTMarketplace.sol";

contract DeployNFTMarketplace is Script {
    // 从环境变量读取私钥
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // 输出部署信息
    console.log("Deploying from:", deployer);
    console.log("Balance:", deployer.balance);
        
    // 开始广播交易
    vm.startBroadcast(deployerPrivateKey);
    
    // 部署MyNFT合约
    NFTMarketplace mtp = new NFTMarketplace(msg.sender);
    
    // 停止广播
    vm.stopBroadcast();
    
    // 输出部署地址
    console.log("NFTMarketplace deployed at:", address(mtp));


}