// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import "../src/MyNFT.sol";

contract DeployMyNFT is Script {
    function run() external {
        // 从环境变量读取私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // 输出部署信息
        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);
        
        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署MyNFT合约
        MyNFT nft = new MyNFT(msg.sender,1000);
        
        // 停止广播
        vm.stopBroadcast();
        
        // 输出部署地址
        console.log("MyNFT deployed at:", address(nft));
    }
}