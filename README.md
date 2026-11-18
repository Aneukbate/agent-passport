# Agent Passport

**An on-chain passport for AI agents.** Only Agent ID holders can check in —
once per UTC day — building streaks and levels that are keyed to their Agent ID.
Every passport is stored fully on-chain and is publicly readable by any account
or contract, so other dApps can compose on top of it as an identity / activity
primitive.

Built for the **Agent ID Hackathon** (Binance Wallet × BNB Chain).

## Live deployment

| | |
|---|---|
| Contract | `AgentPassport` |
| Address | `0xff47c1d24884660d5d7de472cc5172f8ad3a6c6b` |
| Chain | BNB Smart Chain (chainId 56) |
| Deploy tx | `0xbc6082e7c39966bb93cfaa55c2687d64b9c445964add186de2eb7dacc85d6f46` (deterministic CREATE2 via the Arachnid proxy, salt `keccak256("agent-passport-v1")`) |
| Source verification | **Sourcify: exact match** (creation + runtime) — [lookup](https://sourcify.dev/#/lookup/0xff47c1d24884660d5d7de472cc5172f8ad3a6c6b) · [BscScan](https://bscscan.com/address/0xff47c1d24884660d5d7de472cc5172f8ad3a6c6b) |
| Frontend | `index.html` in this repository (single static file, no build step) |

## How Agent ID is used

Agent ID (the soulbound ERC-721 identity issued through the Binance app;
registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` on BSC) is not a login
badge here — it is the passport's **primary key**:

1. **Gate** — `checkIn()` calls `balanceOf(msg.sender)` on the Agent ID
   registry on every check-in and reverts for non-holders. There is no other
   way to create a passport.
2. **Identity keying** — on the first check-in, the passport is bound to the
   holder's Agent ID tokenId, computed on-chain as
   `uint256(keccak256(bytes(handle)))` from the registry's `handleOf(address)`.
   Because Agent IDs are soulbound and one-per-person, a passport can never be
   transferred, sold, or farmed across wallets.
3. **Composable reads** — `getPassport(address)` returns
   `(agentTokenId, totalCheckIns, currentStreak, bestStreak, level, lastDay, firstDay)`
   to anyone, and `agentHandle(address)` resolves the holder's `.ai` name live
   from the registry. Any dApp can gate features on "agents with a passport of
   level ≥ N" or "a live streak ≥ 7 days" with a single view call — a reusable
   proof-of-presence / reputation layer for the Agent ID ecosystem.
   `getPassportPage(offset, limit)` + `passportCount()` support leaderboards
   and indexers.

## What it does

- One check-in per Agent ID per UTC day; consecutive days build a **streak**
  (a missed day resets the live streak; the best streak is kept forever).
- **Level** = 1 + (totalCheckIns − 1) / 7 — a weekly cadence.
- Events `PassportCreated` and `CheckedIn` are emitted for indexers.
- The frontend (`index.html`) connects through the wallet's standard injected
  provider, shows your `.ai` handle, your passport stats, a check-in button,
  and a global leaderboard. Reads use plain JSON-RPC against public BSC
  endpoints — no backend, no accounts, no tracking.

## Owner permissions: NONE

This is a deliberate, verifiable property of the deployed bytecode:

- **No owner. No admin. No proxy / upgrade path. No pause. No setters.**
- **No payable functions and no `receive`/`fallback`** — the contract can
  never hold BNB or tokens, and it never calls `transfer`, `approve`, or any
  token contract. The only external calls are read-only `view` calls to the
  fixed Agent ID registry address.
- Nobody — including the deployer — can alter, delete, freeze, or mint a
  passport for anyone else. A check-in only ever writes the caller's own
  record and moves no assets.

## Hackathon red-line compliance

- ✅ No QR-code / pairing-code wallet login anywhere — standard injected
  wallet connection only; every transaction is shown and confirmed by the
  user in their own wallet.
- ✅ No bypassing of user transaction confirmation; no scheduled or bundled
  transfers; no approvals requested from users (the contract needs none).
- ✅ No collection of seed phrases, private keys, API secrets, or pairing codes.
- ✅ No Binance / BNB branding in the project or contract name.
- ✅ No promises of returns: Agent Passport is a free activity record. It is
  **not an investment, not a token, and promises no rewards or future value**.
  The only cost of a check-in is the network gas fee.
- ✅ Agent ID is never used to look up other people's wallets: the leaderboard
  shows only the public handles and stats of agents who voluntarily checked in.
- ✅ Contract source is open (this repo, MIT) and verified with an exact
  bytecode match on Sourcify.

## Verify the source yourself

Compiler: solc `0.8.28+commit.7893614a`, optimizer enabled, 200 runs,
single source file `AgentPassport.sol`.

- Sourcify: open the [lookup page](https://sourcify.dev/#/lookup/0xff47c1d24884660d5d7de472cc5172f8ad3a6c6b) — status **exact_match**.
- Or reproduce locally: compile `AgentPassport.sol` with the settings above
  (standard-JSON input) and compare the creation bytecode against the deploy
  transaction, and the runtime bytecode against the code at the address.

## Run the frontend

The site is one static file. Serve the repository root with any static host
(e.g. GitHub Pages), or locally:

```bash
python3 -m http.server 8080   # then open http://localhost:8080
```

Open it in a wallet browser (or a desktop browser with a wallet extension),
switch to BNB Smart Chain, and connect. Without a wallet you can still browse
the leaderboard.

## License

MIT — see `LICENSE`.
