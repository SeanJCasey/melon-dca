pragma solidity ^0.4.25;

interface DCAOrderBookInterface {
    // NOTE: enum can't be used in <0.5.0 interfaces,
    // so using uint instead just to get this to compile

    // enum DCAOrderState { None, InProgress, Completed, Cancelled }

    function cancelDCAOrder(uint256 _id) external;

    function checkDCAOrderConversionDue(uint256 _id)
        view
        external
        returns (bool);

    function checkDCAConversionDueAll()
        view
        external
        returns (uint256[] memory);

    function createDCAOrder(
        uint256 _amount,
        address _sourceCurrency,
        address _targetCurrency,
        uint256 _frequency,
        uint8 _batches
    )
        external
        returns (uint256);

    function getDCAOrder(uint256 _id)
        view
        external
        returns (
            uint256 id_,
            uint256 amount_,
            address sourceCurrency_,
            address targetCurrency_,
            uint256 state_,
            uint256 frequency_,
            uint8 batches_,
            uint8 batchesExecuted_,
            uint256 lastConversionTimestamp_,
            uint256 targetCurrencyConverted_,
            uint256 sourceCurrencyConverted_
        );

    function getDCAOrderBatchValue(uint256 _id)
        view
        external
        returns (uint256);

    function getDCAOrderCount() view external returns (uint256);

    function getDCAOrderCountForAccount(address _account)
        view
        external
        returns (uint256);

    function getDCAOrderForAccountIndex(address _account, uint256 _index)
        view
        external
        returns (
            uint256 id_,
            uint256 amount_,
            address sourceCurrency_,
            address targetCurrency_,
            uint256 state_,
            uint256 frequency_,
            uint8 batches_,
            uint8 batchesExecuted_,
            uint256 lastConversionTimestamp_,
            uint256 targetCurrencyConverted_,
            uint256 sourceCurrencyConverted_
        );

    function isDCAOrderAccount(uint256 _id, address _account)
        view
        external
        returns (bool);

    function updateDCAOrderWithConversion(
        uint256 _id,
        uint256 _sourceCurrencyConverted,
        uint256 _targetCurrencyConverted
    )
        external;
}
