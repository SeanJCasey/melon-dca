# Dollar Cost Averaging Challenge (Avantgarde)

## Problem description

The basic challenge is to create an ExchangeAdapter which gives fund managers the option to use DCA.

In implementing DCA you are free to use VulcanSwap, or some simplified version of it with fewer features, or even a solution that does not use VulcanSwap at all.

## Solution:

### 1. Deploy a `DCAOrderBook` contract

I abstracted a `DCAOrderBook` contract from Vulcan Swap and heavily modified it serve the puropses of the adapter. Most importantly, I removed the actual swap execution logic entirely so that this is now *only* an order book. It stores our DCA orders and allows the order owner to make updates to the order storage (e.g., amounts converted and OrderState).

This contract would be deployed on the network the adapter is used on.

### 2. Create a `Uniswappable` contract (to be inherited)

I moved Uniswap execution logic into this contract, which is inhereted by the adapter.

### 3. Deploy a `DCAAdapter` contract

This contract inherits `ExchangeAdapter` and `Uniswappable`.

It uses the `makeOrder` method to create a `DCAOrder` in the deployed `DCAOrderBook`.

This order can then be executed by any caller using `delegatecall` on the `Trading` contract of a specific Fund to invoke `executeDueOrderBatch()`. This method implements all the logic to get the order info from `DCAOrderBook`, swap a single batch, report the swap to the `DCAOrderBook`, move the swapped funds back into the vault, and update the Fund Accounting.

It also allows for `cancelOrder`, which cancels the order both in the `DCAOrderBook` as well as in the Fund.

### Solution notes

- Uniswap factory address

- I'm considering `targetExchange` in the `DCAAdapter` methods to refer to the `DCAOrderBook`. There are 3 ways to change state of the orderbook: `createDCAOrder`, `updateDCAOrderWithConversion`, and `cancelDCAOrder`.

- I set the scopes for access to `DCAOrderBook` in a sensible way for now, but the getter functions for orders might be set to private eventually.

- I left out safemath for simplicity, i.e., not needing to import from OpenZeppelin (I think Melon has its own lib)

- The way we store the Uniswap factory address is not ideal (on the `DCAAdapter`, set and inherited via `Uniswappable`'s constructor) because it doesn't allow for a new factory deployment, but it's fine for this exercise.

- I'm ignoring calculating a min amount of tokens to accept from a Uniswap swap, and ignoring checking a Uniswap pool's liquidity when a `DCAOrder` is created, but those are both risk management checks that should be made.

- I removed all the limitations on a `DCAOrder` (accepted source and target currencies, max and min amounts). Min/max amounts should be decided by the adapter.

- I set the `DCAAdapter` constants for `BATCHES` (7 batches) and `FREQUENCY` (daily) for this exercise.


## Architecture notes:

### Oct 23

- I decided to reference `KyberAdapter` alongside the `MatchingMarketAdapter` because it's more similar to Vulcan Swap's use of Uniswap (taker orders only). Plus, I'm guessing from the namespacing that it has been implemented more recently so is more in-line with recent practices.

- I thought about whether this would be better as a `VulcanSwapAdapter`, or as a `DCAAdapter` (which implements its own logic), but I think even if we go the latter route, we'd still want to just create our own DCA "exchange," (i.e., a standalone feature-complete smart contract) because we need all the same exchange logic regardless.

  - Disadvantage: No granular control over risk management (i.e., can't spot check slippage on orders, need to 100% trust VS to guard against risk on our behalf)

#### BIG PROBLEM: Accounting

There is no way to account for which orders belong to which `Fund`.

VS uses Uniswap's `...TransferInput()` functions to send the target currency directly to the 'owner' of the order (the `msg.sender` at the time the order is created) after a swap.

If the problem were just 1 swap, we could check the difference in token balance of the Adapter contract before and after the swap, but we have no way to do this for subsequent (time-delayed) swaps, and therefore have no method for accounting.

There are a few possible solutions to this:

  1. Implement the DCA order book into its own Adapter, complete with accounting logic and external functions to queue swaps.

  2. Implement the DCA order book as a contract, have the DCAAdapter inheret from it, and do the swaps via the KyberAdapter (or as new Uniswap adapter).

  3. (hacky solution purely for this exercise) Pretend that VS invocation of Uniswap methods custodies and accounts for the funds of its order owners. Even if we did this, the Adapter would still need to have a function to withdraw its swapped tokens, which would need to be triggered somehow... so it's still not a great solution as it leaves these funds outside of the custody of the Fund, which I imagine is a no-no for custody.

### Oct 24

- I decided to approach this with solution 1 above: create a `DCAOrderBook` that is inherited by the `DCAAdapter`.

- I initially approached a DCA order as a `takeOrder`, with the logic that each individual batch is actually a market order (i.e., a "taker" order in the eyes of an exchange).

- After writing out most of the code for this implementation, the Avantgarde team and I realized two critical factors:

  1. DCA orders should actually be made via `makeOrder`, because it involves non-instantaneous settlement. This makes sense because technically, it is "making" an order in the DCA order book.

  2. (much more servere to the architecture) DCA orderbook storage cannot be on the Adapter itself. The adapter is a single deployed contracts that functions as a library for Funds to call via a `delegatecall`. Since this is the case, any kind of storage done via the call would be attempted at the parallel storage slot of the calling contract. TL;DR - this isn't going to work as an inherited contract

- Despite this realization, we decided that I could continue down this path an implement the `DCAOrderBook` as an inherited contract on `DCAAdapter` for the purposes of this exercise.


### Oct 25

- I woke up inspired, and decided to re-write the `DCAOrderBook` into its own externally invoked contract, with the batch exectution logic happening on the `DCAAdapter`. See full solution above.

