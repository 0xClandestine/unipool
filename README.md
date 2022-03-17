<img align="right" width="400" height="150" top="100" src="./assets/readme.png">

# Unipool 🦄 • [![tests](https://github.com/abigger87/femplate/actions/workflows/tests.yml/badge.svg)](https://github.com/abigger87/femplate/actions/workflows/tests.yml) [![lints](https://github.com/abigger87/femplate/actions/workflows/lints.yml/badge.svg)](https://github.com/abigger87/femplate/actions/workflows/lints.yml) ![GitHub](https://img.shields.io/github/license/abigger87/femplate)  ![GitHub package.json version](https://img.shields.io/github/package-json/v/abigger87/femplate)

## Features

* ♻️Invariant imitation
* ✅Removed Uniswap LP fee
* ✅Added swap fee customization
* ♻️Optional TWAP support (to save gas)


## Blueprint

```ml
lib
├─ ds-test — https://github.com/dapphub/ds-test
├─ solmate — https://github.com/Rari-Capital/solmate
src
├─ tests
│  └─ Unipool.t — "Unipool Tests"
└─ Unipool — "A Minimal Unipool Contract"
```

## License

[AGPL-3.0-only](https://github.com/abigger87/unipool/blob/master/LICENSE)

## Acknowledgements

- [foundry](https://github.com/gakonst/foundry)
- [solmate](https://github.com/Rari-Capital/solmate)
- [forge-std](https://github.com/brockelmore/forge-std)
- [foundry-toolchain](https://github.com/onbjerg/foundry-toolchain) by [onbjerg](https://github.com/onbjerg).

## Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._
