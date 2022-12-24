"use strict";
exports.__esModule = true;
require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
require("tsconfig-paths/register");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("solidity-coverage");
var configEnv = require('dotenv').config;
var resolve = require('path').resolve;
configEnv({ path: resolve(__dirname, './.env.local') });
var config = {
    defaultNetwork: 'localhost',
    networks: {
        testnet: {
            url: "https://goerli.infura.io/v3/".concat(process.env.INFURA_PROJECT_ID),
            accounts: [process.env.SIGNER_PRIVATE_KEY || ''],
            chainId: 5
        },
        mainnet: {
            url: "https://mainnet.infura.io/v3/".concat(process.env.INFURA_PROJECT_ID),
            accounts: [process.env.SIGNER_PRIVATE_KEY || ''],
            gas: 10000000000000
        },
        hardhat: {
            chainId: 5,
            gasPrice: 225000000000,
            throwOnTransactionFailures: true,
            loggingEnabled: true,
            forking: {
                url: "https://goerli.infura.io/v3/".concat(process.env.INFURA_PROJECT_ID),
                enabled: true,
                blockNumber: 7849200
            }
        }
    },
    etherscan: {
        apiKey: {
            goerli: process.env.ETHERSCAN_API_KEY,
            mainnet: process.env.ETHERSCAN_API_KEY
        }
    },
    solidity: {
        version: '0.8.9',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    }
};
exports["default"] = config;
