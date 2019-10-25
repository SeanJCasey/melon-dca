pragma solidity ^0.4.25;

import './IERC20.sol';
import './UniswapFactoryInterface.sol';
import './UniswapExchangeInterface.sol';

contract Uniswappable {

    // NOTE: I think we'd prefer to pass in the exchange address from
    // the DCAAdapter contract, but doing it like this for simplicity
    UniswapFactoryInterface internal factory;

    constructor(address _uniswapFactory) internal {
        factory = UniswapFactoryInterface(_uniswapFactory);
    }

    function exchangeEthToToken(
        address _targetCurrency,
        uint256 _amountSourceCurrency
    )
        internal
        returns (uint256 amountReceived_)
    {
        address exchangeAddress = factory.getExchange(_targetCurrency);
        UniswapExchangeInterface exchange = UniswapExchangeInterface(exchangeAddress);

        // TODO: Set dynamic minimums for tokens to receive here and in
        // other swap functions below
        uint256 min_tokens = 1;
        uint256 deadline = now + 300;
        amountReceived_ = exchange.ethToTokenSwapInput.value(
            _amountSourceCurrency
        )
        (
            min_tokens,
            deadline
        );
    }

    function exchangeTokenToEth(
        address _sourceCurrency,
        uint256 _amountSourceCurrency
    )
        internal
        returns (uint256 amountReceived_)
    {
        address exchangeAddress = factory.getExchange(_sourceCurrency);
        UniswapExchangeInterface exchange = UniswapExchangeInterface(exchangeAddress);

        uint256 min_eth = 1;
        uint256 deadline = now + 300;

        IERC20(_sourceCurrency).approve(exchangeAddress, _amountSourceCurrency);
        amountReceived_ = exchange.tokenToEthSwapInput(
            _amountSourceCurrency,
            min_eth,
            deadline
        );
    }

    function exchangeTokenToToken(
        address _sourceCurrency,
        address _targetCurrency,
        uint256 _amountSourceCurrency
    )
        internal
        returns (uint256 amountReceived_)
    {
        address exchangeAddress = factory.getExchange(_sourceCurrency);
        UniswapExchangeInterface exchange = UniswapExchangeInterface(exchangeAddress);

        uint256 min_eth_intermediary = 1;
        uint256 min_tokens_bought = 1;
        uint256 deadline = now + 300;

        IERC20(_sourceCurrency).approve(exchangeAddress, _amountSourceCurrency);
        amountReceived_ = exchange.tokenToTokenSwapInput(
            _amountSourceCurrency,
            min_tokens_bought,
            min_eth_intermediary,
            deadline,
            _targetCurrency
        );
    }
}
