// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { BGT } from "./BGT.sol";
import { BgtERC1155 } from "./BgtERC1155.sol";
import { BgtNftStakingReward } from "./BgtNftStakingReward.sol";
import { BgtNftExchange } from "./BgtNftExchange.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";


contract BgtNftStakingEntry is PausableUpgradeable, ERC1155HolderUpgradeable {
    uint256 private _stakedNftTokenId;
    address private _owner;
    address private _nftAddr; //BgtERC1155Addr
    address private _nftExchangeAddr;
    address private _nftStakingRewardAddr;
    string  private _rootCode;
    mapping(address => bool) private _communityUsers;
    mapping(string => bool) private _stakedCodes;

    function initialize(
        address nftAddr
    ) public initializer {
        _owner = msg.sender;
        __Pausable_init();
        __ERC1155Holder_init();
        _stakedNftTokenId = 2;
        _nftAddr = nftAddr;
        _rootCode = "026e9732ff502fbf0584564cce3a165b5d3a6c25ad7514c46f3c51439d4aa1d152";
        _stakedCodes[_rootCode] = true;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function stakeNFT(string memory inviteCode, string memory ownerCode, uint256 amount) external whenNotPaused {
        address user = msg.sender;
        require(amount > 0, "BgtNftStakingEntry: amount error");
        if (_communityUsers[user]) {
            (, , uint256 buyAmount) = BgtNftExchange(_nftExchangeAddr).nft2000User(user);
            uint256 stakedNumbers = BgtNftStakingReward(_nftStakingRewardAddr).stakedNumbers(user);
            require(stakedNumbers + amount <= buyAmount, "BgtNftStakingEntry: not allowed");
        } else {
            require(_stakedCodes[inviteCode], "BgtNftStakingEntry: not allowed");
        }

        BgtERC1155(_nftAddr).safeTransferFrom(user, address(this), _stakedNftTokenId, amount, bytes(""));

        if (!_communityUsers[user]) { //community user's InviteCode not work
            _stakedCodes[ownerCode] = true;
        }

        BgtNftStakingReward(_nftStakingRewardAddr).stakeNFT(user, inviteCode, amount, _communityUsers[user]);
    }

    
    function burnNft(uint256 amount) external onlyOwner {
        BgtERC1155(_nftAddr).burn(_stakedNftTokenId, amount, 0);
    }

    function setRootCode(string memory rootCode) external onlyOwner {
        _stakedCodes[_rootCode] = false;
        _rootCode = rootCode;
        _stakedCodes[_rootCode] = true;
    }

    function setNftExchangeAddr(address nftExchangeAddr) external onlyOwner{
        _nftExchangeAddr = nftExchangeAddr;
    }

     function setNftStakingRewardAddr(address nftStakingRewardAddr) external onlyOwner{
        _nftStakingRewardAddr = nftStakingRewardAddr;
    }

    function setCommunityUser(address user, bool isCommunityUser) external {
        require(msg.sender == _nftExchangeAddr, "BgtNftStakingEntry: not allowed");
        _communityUsers[user] = isCommunityUser;
    }

    function codeStaked(string memory code) public view returns(bool) {
        return _stakedCodes[code];
    }

    function owner() external view returns(address){
        return _owner;
    }
}
