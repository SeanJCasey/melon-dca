pragma solidity ^0.4.25;

// TODO: Add actual contracts to import the below:
// import "WETH.sol";
// import "Hub.sol";
// import "Trading.sol";
// import "Vault.sol";
// import "Accounting.sol";
// import "ExchangeAdapter.sol";

import "./lib/DCAOrderBookInterface.sol";

/// @title DCAAdapter Contract
/// @author Sean Casey <sean@avantgarde.com> <-- LOL
/// @notice Adapter between Melon and a DCAOrderBook using Uniswap
contract DCAAdapter is ExchangeAdapter, Uniswappable {

    // NOTE: Use constants for purposes of this exercise
    uint8 constant BATCHES = 7;
    uint constant FREQUENCY = 1 days;

    function executeDueOrderBatch(
        uint DCAOrderId,
        address targetExchange
    )
        public
    {
        Hub hub = getHub();
        Vault vault = Vault(hub.vault());
        DCAOrderBookInterface orderBook = DCAOrderBookInterface(targetExchange);

        // NOTE: Is this always ok to assume native asset is WETH?
        address nativeAsset = Accounting(hub.accounting()).NATIVE_ASSET();

        // TODO: require this contract is the DCAOrder owner
        require (
            orderBook.isDCAOrderAccount(DCAOrderId, address(this)),
            "executeDueOrderBatch: DCAOrderId is not for this fund"
        );

        if (orderBook.checkDCAOrderConversionDue(DCAOrderId) == true) {

            // Get DCA order info
            address makerAsset;
            address takerAsset;
            (,, makerAsset, takerAsset, ,,,,,,) = orderBook.getDCAOrder(DCAOrderId);

            // Get batch value for this order
            uint256 batchValue = orderBook.getDCAOrderBatchValue(DCAOrderId);

            // Map ETH to WETH
            if (makerAsset == address(0)) makerAsset = nativeAsset;
            if (takerAsset == address(0)) takerAsset = nativeAsset;

            // Take value from vault
            vault.withdraw(makerAsset, batchValue);

            // If makerAsset is WETH
            if (makerAsset == nativeAsset) {
                WETH(nativeAsset).withdraw(batchValue);
            }

            // Exchange via Uniswap
            uint256 amountReceived;
            if (takerAsset == nativeAsset) {
                amountReceived = exchangeTokenToEth(
                    makerAsset,
                    batchValue
                );
            }
            else if (makerAsset == nativeAsset) {
                amountReceived = exchangeEthToToken(
                    takerAsset,
                    batchValue
                );
            }
            else {
                amountReceived = exchangeTokenToToken(
                    makerAsset,
                    takerAsset,
                    batchValue
                );
            }

            // Update order in DCA book
            orderBook.updateDCAOrderWithConversion(
                DCAOrderId,
                batchValue,
                amountReceived
            );

            // Convert ETH to WETH
            if (takerAsset == nativeAsset) {
                WETH(nativeAsset).deposit.value(amountReceived)();
            }

            // Return assets to vault and update accounting
            getAccounting().addAssetToOwnedAssets(takerAsset);
            getAccounting().updateOwnedAssets();
            getTrading().returnAssetToVault(takerAsset);

            // TODO: Set correct values... should it reflect the amount
            // in this batch, or the DCA Order overall?
            getTrading().orderUpdateHook(
                targetExchange,
                bytes32(0),
                Trading.UpdateType.take,
                [makerAsset, takerAsset],
                [amountReceived, batchValue, batchValue]
            );
        }
    }

    // Responsibilities of makeOrder are:
    // - check sender
    // - check fund not shut down
    // - check price recent <-- NOTE: ignoring price for exercise
    // - check risk management passes
    // - approve funds to be traded (if necessary)
    // - make order on the exchange
    // - check order was made (if possible)
    // - place asset in ownedAssets if not already tracked
    /// @notice Makes an order on the selected exchange
    /// @dev These orders are not expected to settle immediately
    /// @param targetExchange Address of the exchange
    /// @param orderAddresses [2] Order maker asset
    /// @param orderAddresses [3] Order taker asset
    /// @param orderValues [0] Maker token quantity
    function makeOrder(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes32 identifier,
        bytes makerAssetData,
        bytes takerAssetData,
        bytes signature
    ) public onlyManager notShutDown {
        address makerAsset = orderAddresses[2];
        address takerAsset = orderAddresses[3];
        uint makerAssetAmount = orderValues[0];

        DCAOrderBookInterface orderBook = DCAOrderBookInterface(targetExchange);

        // Order parameter checks
        getTrading().updateAndGetQuantityBeingTraded(makerAsset);
        ensureNotInOpenMakeOrder(makerAsset);

        // TODO: Availability - check if there is an available market

        // TODO: Risk management - check if available market has
        // sufficient liquidity for the order volume.
        // I'm ignoring for this exercise.

        // Create DCA Order
        uint orderId = orderBook.createDCAOrder(
            makerAssetAmount,
            makerAsset,
            takerAsset,
            FREQUENCY,
            BATCHES
        );

        // QUESTION: What should takerQuantity be?
        // 3rd amount: fillTakerQuantity
        getTrading().orderUpdateHook(
            targetExchange,
            bytes32(orderId),
            Trading.UpdateType.make,
            [makerAsset, takerAsset],
            [makerAssetAmount, uint(0), uint(0)]
        );

        // NOTE: This actually gives a 1 day buffer because the
        // first batch gets swapped within the same block, so technically
        // should be (BATCHES - 1). But we want a 1 interval buffer to account
        // for expected delays in batch execution (there is a non 0 amount of time
        // it takes for the external caller to queue a swap).
        uint expectedEndTime = FREQUENCY * BATCHES + now;

        getTrading().addOpenMakeOrder(
            targetExchange,
            makerAsset,
            takerAsset,
            orderId,
            expectedEndTime
        );

        emit OrderCreated(orderId);

        // Convert first DCA Order Batch immediately
        executeDueOrderBatch(orderId, targetExchange);
    }

    // responsibilities of cancelOrder are:
    // - check sender is owner, or that order expired, or that fund shut down
    // - remove order from tracking array
    // - cancel order on exchange
    /// @notice Cancels orders that were not expected to settle immediately
    /// @param targetExchange Address of the exchange
    /// @param orderAddresses [2] Order maker asset
    /// @param identifier Order ID on the exchange
    function cancelOrder(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes32 identifier,
        bytes makerAssetData,
        bytes takerAssetData,
        bytes signature
    ) public onlyCancelPermitted(targetExchange, orderAddresses[2]) {
        Hub hub = getHub();
        require(uint(identifier) != 0, "ID cannot be zero");

        DCAOrderBookInterface orderBook = DCAOrderBookInterface(targetExchange);

        address makerAsset;
        (,, makerAsset, ,,,,,,,) = orderBook.getDCAOrder(uint(identifier));
        require(
            address(makerAsset) == orderAddresses[2],
            "Retrieved and passed assets do not match"
        );

        getTrading().removeOpenMakeOrder(targetExchange, makerAsset);

        // TODO: check if DCAOrderState == InProgress, because
        // will revert otherwise. Should account for possibility that
        // order is cancelled in DCAOrderBook contract but not here somehow
        orderBook.cancelDCAOrder(uint(identifier));

        // QUESTION: should return values all be 0?
        // getTrading().orderUpdateHook(
        //     targetExchange,
        //     bytes32(identifier),
        //     Trading.UpdateType.cancel,
        //     [address(0), address(0)],
        //     [uint(0), uint(0), uint(0)]
        // );
    }

}
