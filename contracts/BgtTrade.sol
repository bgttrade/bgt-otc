// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";


contract BgtTrade is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum BuyStatus {ONGOING, CANCELLED, DONE}
    
    struct BuyBgtOrder {
        address buyer;
        uint256 bgtBuyAmount;
        uint256 bgtBoughtAmount;
        uint256 usdtPrice;
        uint256 usdtAmount;
        uint256 usdtCost;
        BuyStatus status;
        uint256 minBuyAmount;
    }

    struct SellBgtOrder {
        address seller;
        uint256 sellerIndex;
        address buyer;
        uint256 buyerIndex;
        uint256 bgtSoldAmount;
        uint256 usdtAmount;
    }

    uint256 constant private PRECISION = 10**30;
    address private  _USDT;
    address private _bgt;
    mapping(address => bool) private _operators;

    mapping(address => uint256) private _buyerIndex;
    mapping(bytes32 => BuyBgtOrder) private _buyBgtOrders;

    mapping(address => uint256) private _sellerIndex;
    mapping(bytes32 => SellBgtOrder) private _sellBgtOrders;

    uint256[50] private __gap;

    uint256 private _fee; //precision=1e4 100/10000=1%
    uint256 constant private FEE_PRECISION = 10**4;
    address private _feeReceiver;


    event Buy(address buyer, uint256 bgtBuyAmount, uint256 usdtPrice, uint256 usdtAmount, uint256 index, uint256 minBuyAmount);
    event CancelBuyOrder(address buyer, uint256 index, uint256 usdtReceivedAmount);
    event Sell(
        address seller,  
        uint256 sellerIndex, 
        address buyer, 
        uint256 buyerIndex, 
        uint256 bgtAmount, 
        uint256 usdtReceivedAmount,
        uint256 commission
    );
    event RefundBuyerUsdt(address buyer, uint256 index, uint256 refundUsdtAmount);

    function initialize(
        address bgt,
        address usdt,
        address operator
    ) public initializer {
        _bgt = bgt;
        _USDT = usdt;
        _operators[operator] = true;

        __Ownable_init();
        __ReentrancyGuard_init();   
    }

    function buy(uint256 bgtBuyAmount, uint256 usdtAmount, uint256 minBuyAmount) external nonReentrant{
        address buyer = msg.sender;

        IERC20Upgradeable(_USDT).safeTransferFrom(
            buyer, 
            address(this), 
            usdtAmount
        );

        uint256 index = _buyerIndex[buyer] + 1; 
        _buyerIndex[buyer] = index;
        _buyBgtOrders[getOrderKey(buyer, index)] = BuyBgtOrder(
            buyer,
            bgtBuyAmount,
            0,
            usdtAmount*PRECISION/bgtBuyAmount,
            usdtAmount,
            0,
            BuyStatus.ONGOING,
            minBuyAmount
        ); 
        emit Buy(buyer, bgtBuyAmount, usdtAmount*PRECISION/bgtBuyAmount, usdtAmount, index, minBuyAmount);
    }

    function cancelBuyOrder(uint256 index) external nonReentrant {
        address buyer = msg.sender;
        BuyBgtOrder storage order = _buyBgtOrders[getOrderKey(buyer, index)];
        require(order.status == BuyStatus.ONGOING && buyer == order.buyer, "BgtTrade: status error");
        order.status = BuyStatus.CANCELLED;
        IERC20Upgradeable(_USDT).safeTransfer(buyer, order.usdtAmount - order.usdtCost);
        emit CancelBuyOrder(buyer, index, order.usdtAmount - order.usdtCost);
    }

    function sell(address buyer, uint256 buyerIndex, uint256 bgtAmount) external nonReentrant{
        BuyBgtOrder storage order = _buyBgtOrders[getOrderKey(buyer, buyerIndex)];
        require(order.status == BuyStatus.ONGOING, "BgtTrade: status error");
        require(bgtAmount >= order.minBuyAmount, "BgtTrade: bgtAmount small");
        require(bgtAmount <= order.bgtBuyAmount - order.bgtBoughtAmount, "BgtTrade: amount error");
        address seller = msg.sender;

        uint256 usdtCost = order.usdtPrice*bgtAmount/PRECISION;
        order.bgtBoughtAmount += bgtAmount;
        order.usdtCost += usdtCost;


        if (order.bgtBoughtAmount == order.bgtBuyAmount) {
            order.status = BuyStatus.DONE;
        }
        uint256 commission = usdtCost * _fee/FEE_PRECISION;
        uint256 usdtReceivedAmount = usdtCost - commission;

        uint256 sellerIndex = _sellerIndex[seller] + 1; 
        _sellerIndex[seller] = sellerIndex;
        _sellBgtOrders[getOrderKey(seller, sellerIndex)] = SellBgtOrder(
            seller,
            sellerIndex,
            buyer,
            buyerIndex,
            bgtAmount,
            usdtReceivedAmount
        ); 
        emit Sell(seller, sellerIndex, buyer, buyerIndex, bgtAmount, usdtReceivedAmount, commission);

        if (order.status == BuyStatus.ONGOING) {
            uint256 leftBgtAmount = order.bgtBuyAmount - order.bgtBoughtAmount;
            if (leftBgtAmount < order.minBuyAmount) {
                order.status = BuyStatus.DONE;
                IERC20Upgradeable(_USDT).safeTransfer(buyer, order.usdtAmount - order.usdtCost);
                emit RefundBuyerUsdt(buyer, buyerIndex, order.usdtAmount - order.usdtCost);
            }
        }

        //transfer bgt from seller to buyer
        IERC20Upgradeable(_bgt).safeTransferFrom(seller, buyer, bgtAmount);

        //transfer usdt from address(this) to seller
        IERC20Upgradeable(_USDT).safeTransfer(seller, usdtReceivedAmount);
        if (commission > 0) {
            IERC20Upgradeable(_USDT).safeTransfer(_feeReceiver, commission);
        }
    }

    function setFee(uint256 fee, address feeReceiver) external onlyOwner {
        _fee = fee;
        _feeReceiver = feeReceiver;
    }

    function getFee() external view returns(uint256) {
        return _fee;
    }

    function getOrderKey(address user, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, index));
    }

    function getBuyerIndex(address buyer) external view returns(uint256) {
        return _buyerIndex[buyer];
    }

    function getSellerIndex(address seller) external view returns(uint256) {
        return _sellerIndex[seller];
    }

    function getBuyOrders(address buyer, uint256[] memory indexes) external view returns(BuyBgtOrder[] memory) {
        BuyBgtOrder[] memory orders = new BuyBgtOrder[](indexes.length);
        for (uint256 i; i < indexes.length; i++) {
            orders[i] = _buyBgtOrders[getOrderKey(buyer, indexes[i])];
        }
        return orders;
    }

    function getSellOrders(address seller, uint256[] memory indexes) external view returns(SellBgtOrder[] memory) {
        SellBgtOrder[] memory orders = new SellBgtOrder[](indexes.length);
        for (uint256 i; i < indexes.length; i++) {
            orders[i] = _sellBgtOrders[getOrderKey(seller, indexes[i])];
        }
        return orders;
    }

}