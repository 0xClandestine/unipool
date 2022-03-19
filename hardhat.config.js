require('dotenv').config()
require('hardhat-deploy');


/* -------------------------------------------------------------------------- */
/*                               HARDHAT CONFIG                               */
/* -------------------------------------------------------------------------- */

module.exports = {
  networks: {
    hardhat: {
    },
    ropsten: {
      url: process.env.ROPSTEN_ALCHEMY,
      accounts: [process.env.PRIVATE_KEY]
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  namedAccounts: {
    deployer: 0
  },
};