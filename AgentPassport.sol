// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the SPACE ID Agent ID registry
///         ("SPACE ID Agent ID", symbol "AI", ERC-721, soulbound).
/// @dev Registry facts verified on-chain + from Sourcify-verified source
///      (contract name: HandleRegistry, solc 0.8.24, exact_match):
///      - tokenId == uint256(keccak256(bytes(handle)))
///      - handleOf(address) returns "" for addresses without an Agent ID
///      - transfers always revert (Soulbound) once minted
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function handleOf(address owner) external view returns (string memory);
    function ownerOfHandle(string calldata handle) external view returns (address);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title AgentPassport
/// @notice An on-chain passport for AI agents. Only Agent ID holders can
///         check in, once per UTC day, building streaks and levels that are
///         keyed to their Agent ID (tokenId). Passport data is publicly
///         readable by any account or contract, so other dApps can compose
///         on top of it as an identity / activity primitive.
///
/// @dev Safety posture (by construction, not by policy):
///      - NO payable functions, NO receive/fallback: the contract can never
///        hold BNB or any token. It never calls transfer/approve on anything.
///      - NO owner, NO admin, NO pause, NO upgrade, NO setters of any kind.
///        Nobody — including the deployer — can alter, delete, or freeze
///        anyone's passport after deployment.
///      - The only external calls are read-only (view) calls to the fixed
///        Agent ID registry address below.
///      - Check-in moves no assets; it only writes the caller's own record.
contract AgentPassport {
    /// @notice The SPACE ID Agent ID registry on BNB Smart Chain (chain 56).
    IAgentIdRegistry public constant AGENT_ID_REGISTRY =
        IAgentIdRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    uint256 internal constant SECONDS_PER_DAY = 86_400;

    struct Passport {
        uint256 agentTokenId; // uint256(keccak256(bytes(handle))) in the registry
        uint64 totalCheckIns; // lifetime check-ins
        uint64 currentStreak; // consecutive UTC days, including the latest one
        uint64 bestStreak; // longest streak ever
        uint64 lastDay; // UTC day number of the latest check-in
        uint64 firstDay; // UTC day number of the first check-in
        bool exists;
    }

    mapping(address => Passport) private _passports;
    address[] private _agents; // every passport holder, in join order (for enumeration)

    event PassportCreated(address indexed agent, uint256 indexed agentTokenId, uint256 day);
    event CheckedIn(
        address indexed agent,
        uint256 indexed agentTokenId,
        uint256 day,
        uint256 totalCheckIns,
        uint256 currentStreak,
        uint256 level
    );

    error NotAgentIdHolder();
    error AlreadyCheckedInToday();

    // ------------------------------------------------------------------
    // Core action
    // ------------------------------------------------------------------

    /// @notice Check in for today (UTC). One check-in per Agent ID per day.
    /// @dev Gated by the registry: the caller must hold an Agent ID
    ///      (balanceOf > 0). First check-in creates the caller's passport and
    ///      binds it to their Agent ID tokenId. Moves no assets.
    function checkIn() external {
        if (AGENT_ID_REGISTRY.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();

        uint256 today = block.timestamp / SECONDS_PER_DAY;
        Passport storage p = _passports[msg.sender];

        if (!p.exists) {
            string memory handle = AGENT_ID_REGISTRY.handleOf(msg.sender);
            p.agentTokenId = uint256(keccak256(bytes(handle)));
            p.firstDay = uint64(today);
            p.exists = true;
            _agents.push(msg.sender);
            emit PassportCreated(msg.sender, p.agentTokenId, today);
        }

        if (p.lastDay == today && p.totalCheckIns != 0) revert AlreadyCheckedInToday();

        // Streak: continues only if the previous check-in was yesterday.
        if (p.totalCheckIns != 0 && p.lastDay == today - 1) {
            p.currentStreak += 1;
        } else {
            p.currentStreak = 1;
        }
        if (p.currentStreak > p.bestStreak) p.bestStreak = p.currentStreak;

        p.totalCheckIns += 1;
        p.lastDay = uint64(today);

        emit CheckedIn(
            msg.sender, p.agentTokenId, today, p.totalCheckIns, p.currentStreak, levelOf(p.totalCheckIns)
        );
    }

    // ------------------------------------------------------------------
    // Public reads (composable identity primitive)
    // ------------------------------------------------------------------

    /// @notice Full passport of any agent address, readable by anyone.
    /// @return agentTokenId The holder's Agent ID tokenId (0 if no passport).
    /// @return totalCheckIns Lifetime check-ins.
    /// @return currentStreak Current streak in days (0 if it has lapsed).
    /// @return bestStreak Longest streak ever.
    /// @return level Passport level derived from totalCheckIns.
    /// @return lastDay UTC day number of the latest check-in.
    /// @return firstDay UTC day number of the first check-in.
    function getPassport(address agent)
        external
        view
        returns (
            uint256 agentTokenId,
            uint256 totalCheckIns,
            uint256 currentStreak,
            uint256 bestStreak,
            uint256 level,
            uint256 lastDay,
            uint256 firstDay
        )
    {
        Passport storage p = _passports[agent];
        if (!p.exists) return (0, 0, 0, 0, 0, 0, 0);
        return (
            p.agentTokenId,
            p.totalCheckIns,
            _liveStreak(p, block.timestamp / SECONDS_PER_DAY),
            p.bestStreak,
            levelOf(p.totalCheckIns),
            p.lastDay,
            p.firstDay
        );
    }

    /// @notice The Agent ID handle (name) bound to an address, read live from
    ///         the registry. Returns "" if the address holds no Agent ID.
    function agentHandle(address agent) external view returns (string memory) {
        return AGENT_ID_REGISTRY.handleOf(agent);
    }

    /// @notice Whether an address already has a passport.
    function hasPassport(address agent) external view returns (bool) {
        return _passports[agent].exists;
    }

    /// @notice Whether an address has already checked in today (UTC).
    function checkedInToday(address agent) external view returns (bool) {
        Passport storage p = _passports[agent];
        return p.exists && p.lastDay == block.timestamp / SECONDS_PER_DAY;
    }

    /// @notice Total number of passports ever created.
    function passportCount() external view returns (uint256) {
        return _agents.length;
    }

    /// @notice Address of the passport holder at `index` (join order).
    function agentAt(uint256 index) external view returns (address) {
        return _agents[index];
    }

    /// @notice A page of passports for leaderboards / indexers.
    /// @dev Unsorted (join order); consumers sort by streak/total as needed.
    function getPassportPage(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory agents, uint256[] memory totals, uint256[] memory streaks)
    {
        uint256 count = _agents.length;
        if (offset >= count) return (new address[](0), new uint256[](0), new uint256[](0));
        uint256 end = offset + limit;
        if (end > count) end = count;
        uint256 n = end - offset;
        agents = new address[](n);
        totals = new uint256[](n);
        streaks = new uint256[](n);
        uint256 today = block.timestamp / SECONDS_PER_DAY;
        for (uint256 i = 0; i < n; i++) {
            address a = _agents[offset + i];
            Passport storage p = _passports[a];
            agents[i] = a;
            totals[i] = p.totalCheckIns;
            streaks[i] = _liveStreak(p, today);
        }
    }

    /// @notice Level for a given lifetime check-in count.
    /// @dev Level 1 on the first check-in, +1 level per 7 further check-ins
    ///      (a weekly cadence): L1 = 1-7, L2 = 8-14, L3 = 15-21, ...
    function levelOf(uint256 totalCheckIns) public pure returns (uint256) {
        if (totalCheckIns == 0) return 0;
        return 1 + (totalCheckIns - 1) / 7;
    }

    /// @dev A stored streak is only "live" if the last check-in was today or
    ///      yesterday; after a missed day it reads as 0 (the stored value is
    ///      reset on the next check-in, and bestStreak is preserved).
    function _liveStreak(Passport storage p, uint256 today) internal view returns (uint256) {
        if (p.lastDay == today || p.lastDay == today - 1) return p.currentStreak;
        return 0;
    }
}
