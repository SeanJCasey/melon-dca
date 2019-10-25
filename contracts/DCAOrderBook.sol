pragma solidity ^0.4.25;

contract DCAOrderBook {
    uint256 internal nextId;

    enum DCAOrderState { None, InProgress, Completed, Cancelled }
    struct DCAOrderInfo {
        address account;
        address sourceCurrency;
        address targetCurrency;
        DCAOrderState state;
        uint256 amount;
        uint256 frequency; // in seconds
        uint256 createdTimestamp;
        uint256 lastConversionTimestamp;
        uint256 sourceCurrencyConverted;
        uint256 targetCurrencyConverted;
        uint8 batches;
        uint8 batchesExecuted;
    }
    mapping(uint256 => DCAOrderInfo) internal idToDCAOrder;
    mapping(address => uint256[]) internal accountToDCAOrderIds;

    modifier onlyDCAOrderAccount(uint256 _id) {
        require(isDCAOrderAccount(_id, msg.sender), "Caller is not order account");
        _;
    }

    event NewDCAOrder(
        address indexed _account,
        uint256 _orderId
    );

    event DCAOrderConversion(
        address indexed _account,
        uint256 _orderId
    );

    event CancelDCAOrder(
        address indexed _account,
        uint256 _orderId
    );

    event CompleteDCAOrder(
        address indexed _account,
        uint256 _orderId
    );

    constructor() public {
        nextId = 1;
    }

    /* External functions */

    function cancelDCAOrder(uint256 _id)
        external
        onlyDCAOrderAccount(_id)
    {
        DCAOrderInfo storage order = idToDCAOrder[_id];
        require(
            idToDCAOrder[_id].state == DCAOrderState.InProgress,
            "cancelDCAOrder: Order is not InProgress"
        );

        idToDCAOrder[_id].state = DCAOrderState.Cancelled;

        emit CancelDCAOrder(order.account, _id);
    }

    // Returns a mapping of bool if conversion is due for order ids as indexes
    function checkDCAOrderConversionDueAll()
        view
        external
        returns (uint256[] memory)
    {
        uint256 totalOrderCount = getDCAOrderCount();
        require(totalOrderCount > 0);

        uint256[] memory coversionDueMap = new uint256[](totalOrderCount);

        for (uint256 i=1; i<=totalOrderCount; i++) {
            if (checkDCAOrderConversionDue(i) == true) coversionDueMap[i-1] = i;
        }

        return coversionDueMap;
    }

    function createDCAOrder(
        uint256 _amount,
        address _sourceCurrency,
        address _targetCurrency,
        uint256 _frequency,
        uint8 _batches
    )
        external
        returns (uint256 id_)
    {
        require(_amount > 0, "createDCAOrder: Amount must be greater than 0");
        require(
            _batches > 1,
            "createDCAOrder: Batches must be greater than 1"
        );
        require(
            _frequency > 0,
            "createDCAOrder: Frequency must be greater than 0"
        );
        require(
            _sourceCurrency != _targetCurrency,
            "createDCAOrder: Source and target currencies cannot be the same"
        );

        DCAOrderInfo memory newOrder = DCAOrderInfo({
            account: msg.sender,
            amount: _amount,
            batches: _batches,
            batchesExecuted: 0,
            createdTimestamp: now,
            frequency: _frequency,
            lastConversionTimestamp: 0,
            sourceCurrency: _sourceCurrency,
            sourceCurrencyConverted: 0,
            state: DCAOrderState.InProgress,
            targetCurrency: _targetCurrency,
            targetCurrencyConverted: 0
        });
        idToDCAOrder[nextId] = newOrder;
        accountToDCAOrderIds[msg.sender].push(nextId);

        emit NewDCAOrder(msg.sender, nextId);

        nextId++;
        return nextId-1;
    }

    // function getDCAOrderForAccountIndex(address _account, uint256 _index)
    //     view
    //     external
    //     returns (
    //         uint256 id_,
    //         uint256 amount_,
    //         address sourceCurrency_,
    //         address targetCurrency_,
    //         DCAOrderState state_,
    //         uint256 frequency_,
    //         uint8 batches_,
    //         uint8 batchesExecuted_,
    //         uint256 lastConversionTimestamp_,
    //         uint256 targetCurrencyConverted_,
    //         uint256 sourceCurrencyConverted_
    //     )
    // {
    //     require(_index < getDCAOrderCountForAccount(_account));

    //     uint256 orderId = accountToDCAOrderIds[_account][_index];
    //     DCAOrderInfo memory order = idToDCAOrder[orderId];

    //     return getDCAOrder(orderId);
    // }

    function updateDCAOrderWithConversion(
        uint256 _id,
        uint256 _sourceCurrencyConverted,
        uint256 _targetCurrencyConverted
    )
        external
        onlyDCAOrderAccount(_id)
    {
        DCAOrderInfo storage order = idToDCAOrder[_id];
        order.lastConversionTimestamp = now;
        order.sourceCurrencyConverted += _sourceCurrencyConverted;
        order.targetCurrencyConverted += _targetCurrencyConverted;

        order.batchesExecuted += 1;
        if (order.batches == order.batchesExecuted) {
            completeDCAOrder(_id);
        }

        emit DCAOrderConversion(order.account, _id);
    }


    /* Public functions */

    function checkDCAOrderConversionDue(uint256 _id)
        view
        public
        returns (bool)
    {
        DCAOrderInfo memory order = idToDCAOrder[_id];

        // Check if order is in Progress
        if (order.state != DCAOrderState.InProgress) return false;

        // Check if the first conversion has been executed
        if (order.lastConversionTimestamp == 0) return true;

        // Check if enough time has elapsed to execute the next conversion
        uint256 timeDelta = now - order.lastConversionTimestamp;
        if (timeDelta < order.frequency) return false;

        return true;
    }

    function getDCAOrder(uint256 _id)
        view
        public
        returns (
            uint256 id_,
            uint256 amount_,
            address sourceCurrency_,
            address targetCurrency_,
            DCAOrderState state_,
            uint256 frequency_,
            uint8 batches_,
            uint8 batchesExecuted_,
            uint256 lastConversionTimestamp_,
            uint256 targetCurrencyConverted_,
            uint256 sourceCurrencyConverted_
        )
    {
        DCAOrderInfo memory order = idToDCAOrder[_id];

        return (
            _id,
            order.amount,
            order.sourceCurrency,
            order.targetCurrency,
            order.state,
            order.frequency,
            order.batches,
            order.batchesExecuted,
            order.lastConversionTimestamp,
            order.targetCurrencyConverted,
            order.sourceCurrencyConverted
        );
    }

    function getDCAOrderBatchValue(uint256 _id)
        view
        external
        returns (uint256)
    {
        DCAOrderInfo memory order = idToDCAOrder[_id];
        uint256 batchValue;
        uint256 remainingBalance = order.amount - order.sourceCurrencyConverted;

        // If final batch or not enough remaining balance, use remaining balance
        if (
            order.batches - order.batchesExecuted == 1 ||
            remainingBalance < batchValue
        ) {
            batchValue = remainingBalance;
        }
        else {
            batchValue = order.amount / uint256(order.batches);
        }

        return batchValue;
    }

    function getDCAOrderCount() view public returns (uint256) {
        return nextId-1;
    }

    // function getDCAOrderCountForAccount(address _account)
    //     view
    //     public
    //     returns (uint256 count_)
    // {
    //     return accountToDCAOrderIds[_account].length;
    // }

    function isDCAOrderAccount(uint256 _id, address _account)
        view
        public
        returns (bool)
    {
        require(
            idToDCAOrder[_id].state != DCAOrderState.None,
            "isOrderAccount: Order does not exist"
        );
        return idToDCAOrder[_id].account == _account;
    }


    /* Internal functions */

    function completeDCAOrder(uint256 _id) internal {
        DCAOrderInfo storage order = idToDCAOrder[_id];
        order.state = DCAOrderState.Completed;
        emit CompleteDCAOrder(order.account, _id);
    }
}
