// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./PriceFeed.sol";

/**
 * @title Arena
 * @notice Paper-trading competitions with risk-adjusted scoring on Elysium.
 * Scoring: return_bps * 10000 / max(maxDrawdownBps, 100)
 */
contract Arena {
    struct Contest {
        uint256 id;
        uint256 startTime;
        uint256 duration;
        uint256 startCash;
        uint256 entryFee;
        uint256 maxPlayers;
        uint256 playerCount;
        uint256 prizePool;
        bool closed;
        bool finalized;
        address winner;
        uint256[3] finalPrices;
    }

    struct Player {
        bool joined;
        int256 cash;
        mapping(uint256 => int256) position;
        int256 peakEquity;
        uint256 maxDrawdownBps;
        uint256 joinedAt;
        bool eliminated;
    }

    address public owner;
    PriceFeed public priceFeed;

    uint256 public nextContestId = 1;
    mapping(uint256 => Contest) public contests;
    mapping(uint256 => mapping(address => Player)) private players;
    mapping(uint256 => address[]) public contestPlayers;

    uint256 public constant MAX_PLAYERS = 16;
    uint256 public constant NUM_ASSETS = 3;
    uint256 public constant PRICE_STALENESS = 5 minutes;
    uint256 public constant MAX_EXPOSURE_BPS = 20000;

    event ContestCreated(uint256 indexed contestId, uint256 duration, uint256 startCash, uint256 entryFee, uint256 maxPlayers);
    event Joined(uint256 indexed contestId, address indexed player, uint256 joinedAt);
    event Traded(uint256 indexed contestId, address indexed player, uint256 assetId, int256 sizeDelta, uint256 price, int256 newPosition, int256 newCash);
    event Marked(uint256 indexed contestId, address indexed player, int256 equity, uint256 maxDrawdownBps);
    event ContestClosed(uint256 indexed contestId, uint256[3] finalPrices);
    event Finalized(uint256 indexed contestId, address winner, uint256 prizePool);
    event Claimed(uint256 indexed contestId, address winner, uint256 amount);

    error OnlyOwner();
    error ContestNotFound();
    error ContestEnded();
    error ContestNotEnded();
    error ContestAlreadyClosed();
    error ContestNotClosed();
    error AlreadyJoined();
    error NotJoined();
    error ContestFull();
    error PriceStale();
    error InvalidSize();
    error ExposureExceeded();
    error AlreadyFinalized();
    error NotWinner();
    error NothingToClaim();
    error AdminCannotJoin();
    error TransferFailed();
    error PokeAfterClose();

    constructor(address _priceFeed) {
        owner = msg.sender;
        priceFeed = PriceFeed(_priceFeed);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function createContest(uint256 duration, uint256 startCash, uint256 entryFee, uint256 maxPlayers) external onlyOwner returns (uint256 contestId) {
        require(duration > 0, "duration=0");
        require(startCash > 0, "startCash=0");
        require(maxPlayers > 0 && maxPlayers <= MAX_PLAYERS, "bad maxPlayers");

        contestId = nextContestId++;
        Contest storage c = contests[contestId];
        c.id = contestId;
        c.startTime = block.timestamp;
        c.duration = duration;
        c.startCash = startCash;
        c.entryFee = entryFee;
        c.maxPlayers = maxPlayers;

        emit ContestCreated(contestId, duration, startCash, entryFee, maxPlayers);
    }

    function join(uint256 contestId) external payable {
        if (msg.sender == owner) revert AdminCannotJoin();

        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (block.timestamp >= c.startTime + c.duration) revert ContestEnded();
        if (c.closed || c.finalized) revert ContestAlreadyClosed();
        if (players[contestId][msg.sender].joined) revert AlreadyJoined();
        if (c.playerCount >= c.maxPlayers) revert ContestFull();
        require(msg.value == c.entryFee, "wrong entry fee");

        Player storage p = players[contestId][msg.sender];
        p.joined = true;
        p.cash = int256(c.startCash);
        p.peakEquity = int256(c.startCash);
        p.maxDrawdownBps = 0;
        p.joinedAt = block.timestamp;

        contestPlayers[contestId].push(msg.sender);
        c.playerCount += 1;
        c.prizePool += msg.value;

        emit Joined(contestId, msg.sender, block.timestamp);
    }

    function trade(uint256 contestId, uint256 assetId, int256 sizeDelta) external {
        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (block.timestamp >= c.startTime + c.duration) revert ContestEnded();
        if (c.closed || c.finalized) revert ContestAlreadyClosed();

        Player storage p = players[contestId][msg.sender];
        if (!p.joined) revert NotJoined();
        if (p.eliminated) revert("eliminated");
        if (sizeDelta == 0) revert InvalidSize();
        if (assetId >= NUM_ASSETS) revert("bad asset");

        (uint256 price, uint256 priceTs) = priceFeed.getPrice(assetId);
        if (price == 0) revert("price not set");
        if (block.timestamp > priceTs + PRICE_STALENESS) revert PriceStale();

        uint256 oldExposure = _grossExposure(contestId, msg.sender, false);

        int256 cost = (sizeDelta * int256(price)) / 1e8;
        p.cash -= cost;
        p.position[assetId] += sizeDelta;

        uint256 newExposure = _grossExposure(contestId, msg.sender, false);

        if (newExposure > oldExposure) {
            int256 equity = _equity(contestId, msg.sender, false);
            if (equity <= 0 || newExposure * 10000 > uint256(equity) * MAX_EXPOSURE_BPS) {
                p.cash += cost;
                p.position[assetId] -= sizeDelta;
                revert ExposureExceeded();
            }
        }

        _mark(contestId, msg.sender, false);

        emit Traded(contestId, msg.sender, assetId, sizeDelta, price, p.position[assetId], p.cash);
    }

    function closeContest(uint256 contestId) external {
        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (block.timestamp < c.startTime + c.duration) revert ContestNotEnded();
        if (c.closed) revert ContestAlreadyClosed();
        if (c.finalized) revert AlreadyFinalized();

        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            (uint256 price, ) = priceFeed.getPrice(i);
            c.finalPrices[i] = price;
        }

        c.closed = true;

        address[] storage list = contestPlayers[contestId];
        for (uint256 i = 0; i < list.length; i++) {
            _mark(contestId, list[i], true);
        }

        emit ContestClosed(contestId, c.finalPrices);
    }

    function finalize(uint256 contestId) external {
        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (!c.closed) revert ContestNotClosed();
        if (c.finalized) revert AlreadyFinalized();

        address[] storage list = contestPlayers[contestId];
        address bestPlayer = address(0);
        int256 bestScore = type(int256).min;
        uint256 bestJoinedAt = type(uint256).max;

        for (uint256 i = 0; i < list.length; i++) {
            address player = list[i];
            int256 score = getScore(contestId, player);
            uint256 joinedAt = players[contestId][player].joinedAt;

            if (score > bestScore || (score == bestScore && joinedAt < bestJoinedAt)) {
                bestScore = score;
                bestPlayer = player;
                bestJoinedAt = joinedAt;
            }
        }

        c.finalized = true;
        c.winner = bestPlayer;

        emit Finalized(contestId, bestPlayer, c.prizePool);
    }

    function claim(uint256 contestId) external {
        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (!c.finalized) revert ContestNotClosed();
        if (msg.sender != c.winner) revert NotWinner();
        if (c.prizePool == 0) revert NothingToClaim();

        uint256 amount = c.prizePool;
        c.prizePool = 0;

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Claimed(contestId, msg.sender, amount);
    }

    function poke(uint256 contestId, address player) external {
        Contest storage c = contests[contestId];
        if (c.id == 0) revert ContestNotFound();
        if (c.closed || c.finalized) revert PokeAfterClose();
        if (!players[contestId][player].joined) revert NotJoined();
        _mark(contestId, player, false);
    }

    function getEquity(uint256 contestId, address player) public view returns (int256) {
        Contest storage c = contests[contestId];
        return _equity(contestId, player, c.closed);
    }

    function getScore(uint256 contestId, address player) public view returns (int256 score) {
        Contest storage c = contests[contestId];
        Player storage p = players[contestId][player];
        if (!p.joined) return 0;
        if (p.eliminated) return type(int256).min;

        int256 equity = _equity(contestId, player, c.closed);
        int256 startCash = int256(c.startCash);

        int256 returnBps = ((equity - startCash) * 10000) / startCash;
        uint256 ddBps = p.maxDrawdownBps < 100 ? 100 : p.maxDrawdownBps;

        score = (returnBps * 10000) / int256(ddBps);
    }

    function getPlayer(uint256 contestId, address player) external view returns (
        bool joined, int256 cash, int256 equity, int256 peakEquity,
        uint256 maxDrawdownBps, uint256 joinedAt, bool eliminated, int256 score
    ) {
        Contest storage c = contests[contestId];
        Player storage p = players[contestId][player];
        joined = p.joined;
        cash = p.cash;
        equity = _equity(contestId, player, c.closed);
        peakEquity = p.peakEquity;
        maxDrawdownBps = p.maxDrawdownBps;
        joinedAt = p.joinedAt;
        eliminated = p.eliminated;
        score = getScore(contestId, player);
    }

    function getContestPlayers(uint256 contestId) external view returns (address[] memory) {
        return contestPlayers[contestId];
    }

    function getFinalPrices(uint256 contestId) external view returns (uint256[3] memory) {
        return contests[contestId].finalPrices;
    }

    function _price(uint256 contestId, uint256 assetId, bool useFinal) internal view returns (uint256) {
        if (useFinal) {
            return contests[contestId].finalPrices[assetId];
        }
        (uint256 price, ) = priceFeed.getPrice(assetId);
        return price;
    }

    function _equity(uint256 contestId, address player, bool useFinal) internal view returns (int256 equity) {
        Player storage p = players[contestId][player];
        equity = p.cash;
        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            uint256 price = _price(contestId, i, useFinal);
            equity += (p.position[i] * int256(price)) / 1e8;
        }
    }

    function _grossExposure(uint256 contestId, address player, bool useFinal) internal view returns (uint256 exposure) {
        Player storage p = players[contestId][player];
        for (uint256 i = 0; i < NUM_ASSETS; i++) {
            uint256 price = _price(contestId, i, useFinal);
            int256 pos = p.position[i];
            uint256 absPos = pos >= 0 ? uint256(pos) : uint256(-pos);
            exposure += (absPos * price) / 1e8;
        }
    }

    function _mark(uint256 contestId, address player, bool useFinal) internal {
        Player storage p = players[contestId][player];
        int256 equity = _equity(contestId, player, useFinal);

        if (equity > p.peakEquity) {
            p.peakEquity = equity;
        }

        if (p.peakEquity > 0) {
            int256 drawdown = p.peakEquity - equity;
            if (drawdown > 0) {
                uint256 ddBps = uint256((drawdown * 10000) / p.peakEquity);
                if (ddBps > p.maxDrawdownBps) {
                    p.maxDrawdownBps = ddBps;
                }
            }
        }

        if (equity <= 0) {
            p.eliminated = true;
        }

        emit Marked(contestId, player, equity, p.maxDrawdownBps);
    }
}
