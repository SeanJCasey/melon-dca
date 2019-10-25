const DCAOrderBook = artifacts.require("./DCAOrderBook");

module.exports = deployer => {
    deployer.deploy(DCAOrderBook);
};
