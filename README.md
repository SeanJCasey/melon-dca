# Dollar Cost Averaging Challenge (Avantgarde)

## Problem description

The basic challenge is to create an ExchangeAdapter which gives fund managers the option to use DCA.

In implementing DCA you are free to use VulcanSwap, or some simplified version of it with fewer features, or even a solution that does not use VulcanSwap at all.

## Notes:

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
