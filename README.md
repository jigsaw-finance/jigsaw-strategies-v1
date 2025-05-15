# Jigsaw Strategies

<p align="center">
  <img src="https://github.com/jigsaw-finance/jigsaw-lite/assets/102415071/894b1ec7-dcbd-4b2d-ac5d-0a9d0df26313" alt="jigsaw 2"><br>
  <a href="https://github.com/jigsaw-finance/jigsaw-lite/actions/workflows/test.yml">
    <img src="https://github.com/jigsaw-finance/jigsaw-lite/actions/workflows/test.yml/badge.svg" alt="test">
  </a>
  <a href="https://github.com/jigsaw-finance/jigsaw-lite/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT">
  </a>
  <img alt="GitHub commit activity (branch)" src="https://img.shields.io/github/commit-activity/m/jigsaw-finance/jigsaw-lite">
</p>

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

Jigsaw Strategies are specialized contracts that enable users of the Jigsaw Protocol to invest their collateral into pre-approved third-party protocols to generate yield and rewards.

These strategies allow collateral to simultaneously accrue returns while still being utilized within the primary protocol.

The strategies are located in the /src directory. The current list is not exhaustive, with more strategies planned for future implementation.

For further details, please consult the documentation.

## Setup

Project was built using [Foundry](https://book.getfoundry.sh/). Refer to installation instructions [here](https://github.com/foundry-rs/foundry#installation).

This project uses [just](https://just.systems/man/en/) to run project-specific commands. Refer to installation instructions [here](https://github.com/casey/just?tab=readme-ov-file#installation).

```sh
git clone git@github.com:jigsaw-finance/jigsaw-strategies-v1.git
cd jigsaw-strategies-v1
forge install
```

## Commands

To make it easier to perform some tasks within the repo, a few commands are available through a justfile:

### Build Commands

| Command         | Action                                           |
| --------------- | ------------------------------------------------ |
| `clean-all`     | Description                                      |
| `install-vyper` | Install the Vyper venv                           |
| `install`       | Install the Modules                              |
| `update`        | Update Dependencies                              |
| `build`         | Build                                            |
| `format`        | Format code                                      |
| `remap`         | Update remappings.txt                            |
| `clean`         | Clean artifacts, caches                          |
| `docs`          | Generate documentation for Solidity source files |

### Test Commands

| Command        | Description   |
| -------------- | ------------- |
| `test-all`     | Run all tests |
| `coverage-all` | Run coverage  |

Specific tests can be run using `forge test` conventions, specified in more detail in the Foundry [Book](https://book.getfoundry.sh/reference/forge/forge-test#test-options).

## Audit Reports

### Upcoming Release

| Auditor  | Strategy                | Report Link                                                        |
| -------- | ----------------------- | ------------------------------------------------------------------ |
| Halborn | AaveV3Strategy          | https://www.halborn.com/audits/jigsaw-finance/aave-strategies-v1   |
| Halborn | DineroStrategy          | https://www.halborn.com/audits/jigsaw-finance/dinero-strategies-v1 |
| Halborn | IonStrategy             | https://www.halborn.com/audits/jigsaw-finance/ion-strategies-v1    |
| Halborn | PendleStrategy          | https://www.halborn.com/audits/jigsaw-finance/pendle-strategies-v1 |
| Halborn | ReservoirSavingStrategy |                                                                    |

## About Jigsaw

Jigsaw is a CDP-based stablecoin protocol that brings full flexibility and composability to your collateral through the concept of “dynamic collateral”.

Jigsaw leverages crypto’s unique permissionless composability to enable dynamic collateral in a fully non-custodial way.
Dynamic collateral is the missing piece of DeFi for unlocking unparalleled flexibility and capital efficiency by boosting your yield.

---

<p align="center">
</p>
