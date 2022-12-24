# NFT Membership with monthly payment plan

This project demonstrates is a prototype for a NFT payment plan based membership.

## Overview

This simple protocol is designed to be used with any protocol which intends to turn an NFT into a proof of membership token. This contract also allows any NFT membership to be paid for in interest-free instalments. 

Payments for the membership can be made in both FIAT & Native Currency. Payments made in Native Currency can be processed directly by the user interacting with the contract, however FIAT payments need to be accounted for by priveliged actors. We have a "Payment Processor Engine" in current works which is responsible for accounting for Off-Chain payments.

> The current implementation of this payment plan membership is designed to be integrated with [The1Club's](https://www.1club.io/) Membership Scheme which incrementally increases the membership price for new members.

### Memberships are non-refundable.

Once a payment plan has been completed, the user is eligible to claim their Membership NFT.

## To run unit tests

```
npx hardhat test test/PaymentPlan.unit.js
```
