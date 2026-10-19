// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PriceFeed
 * @notice Owner-controlled price feed for Elysium Arena paper trading.
 *         Prices are set manually. This is intentionally simulated.
 */
contract PriceFeed {
    address public owner;

    struct PriceData {
        uint256 price;      // 8 decimals
        uint256 timestamp;
    }

    mapping(uint256 => PriceData) public prices;

    event PriceUpdated(uint256 indexed assetId, uint256 price, uint256 timestamp);

    error OnlyOwner();
    error InvalidPrice();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function setPrice(uint256 assetId, uint256 price) external onlyOwner {
        if (price == 0) revert InvalidPrice();
        prices[assetId] = PriceData({
            price: price,
            timestamp: block.timestamp
        });
        emit PriceUpdated(assetId, price, block.timestamp);
    }

    function getPrice(uint256 assetId) external view returns (uint256 price, uint256 timestamp) {
        PriceData memory data = prices[assetId];
        return (data.price, data.timestamp);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }
}
