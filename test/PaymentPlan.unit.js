const { expect, assert } = require("chai");
const { ethers } = require("hardhat");
// const PaymentPlanABI  = require("../artifacts/contracts/PaymentPlan.sol/PaymentPlan.json");
// const PaymentPlanAddress = "0x7ba1DA48695eBf578a0A242149BE41c85A05ade5"
const OneClubAddress = "0x9ac0169E2396f6eD2878a66D866244319D1f2290"
 
const Voucher = {
  tokenId: 1,
  stakePeriod: 1,
  signature: ethers.utils.toUtf8Bytes("sig")
}

//Run Test - npx hardhat test test/PaymentPlan.unit.js --network hardhat
//Run Verify - npx hardhat verify --network testnet address params
//Run Coverage - npx hardhat coverage --testfiles test/PaymentPlan.unit.js --network hardhat

describe("PaymentPlan", function () {
    let paymentPlan;
    let owner;
    let addr1;
    let addr2;
    let addrs;

    /**
     * @dev for state of goerli testnet
     * allows us to integrate @CHAINLINK price feeds
     */
    beforeEach(async function () {
      await ethers.provider.send(
        "hardhat_reset",
        [
            {
                forking: {
                    jsonRpcUrl: `https://goerli.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
                    blockNumber: 7849200,
                }
            }
        ]
      );
      
      [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();
      
      // load instance of PaymentPlan contract
      PaymentPlan = await ethers.getContractFactory("PaymentPlan");
      paymentPlan = await PaymentPlan.connect(owner).deploy(
        OneClubAddress,
        1,
        6
      );

    })
     
    describe("PaymentPlan", function () {
        it("Creates a new payment plan in ETH & emits event", async function () {
            const tx = await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const args = event.args;
            expect(args[0]).to.equal(addr1.address);
        })
        it("Creates a new payment plan in FIAT & emits event", async function () {
            const tx = await paymentPlan.connect(owner).fiatNewPlan(addr1.address, ethers.utils.parseEther("63"));
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const args = event.args;
            expect(args[0]).to.equal(addr1.address);
        })
        describe("PaymentPlan - Unpaid Instalments", function () {
          beforeEach(async function () {
            await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
            await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"));
            await network.provider.send("evm_mine")
            await network.provider.send("evm_increaseTime", [2.678e+6]);
          })
          it("Pays an instalment & emits event", async function () {
            const tx = await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.042")});
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const args = event.args;
            expect(args[0]).to.equal(addr1.address);
          })
          it("Pays an instalment in FIAT & emits event", async function () {
            const tx = await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("63"));
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const args = event.args;
            expect(args[0]).to.equal(addr2.address);
          })
        })
        describe("Payment Plan - Cancel Membership", function () {
          beforeEach(async function () {
            await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
            await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"));
            await network.provider.send("evm_mine")
            await network.provider.send("evm_increaseTime", [2.678e+6]);
          })
          it("Cancels a payment plan & emits event", async function () {
            const tx = await paymentPlan.connect(addr1).cancelPlan();
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const eventStatus = event.event
            const args = event.args;
            expect(eventStatus).to.equal("PaymentCancelled");
            expect(args[0]).to.equal(addr1.address);
          })
          it("Cancels a payment plan in FIAT & emits event", async function () {
            const tx = await paymentPlan.connect(owner).fiatCancelPlan(addr2.address);
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const eventStatus = event.event
            const args = event.args;
            expect(eventStatus).to.equal("PaymentCancelled");
            expect(args[0]).to.equal(addr2.address);
          })
        })
        describe("Payment Plan - Claim membership", function () {
          beforeEach(async function () {
            await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
            await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"));
            await network.provider.send("evm_mine")
            await network.provider.send("evm_increaseTime", [2.678e+6]);
            await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.25")}); // Mock full payment
            await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("1000")); // Mock full payment
          })
          it("Claims membership & emits event", async function () {
            const tx = await paymentPlan.connect(addr1).claimMembership(addr1.address, Voucher);
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const eventStatus = event.event
            const args = event.args;
            expect(eventStatus).to.equal("MembershipClaimed");
            expect(args[0]).to.equal(addr1.address);
          })
          it("Claims membership in FIAT & emits event", async function () {
            const tx = await paymentPlan.connect(owner).claimMembership(addr2.address, Voucher);
            const receipt = await tx.wait();
            const event = receipt.events[0];
            const eventStatus = event.event
            const args = event.args;
            expect(eventStatus).to.equal("MembershipClaimed");
            expect(args[0]).to.equal(addr2.address);
          })
        })
      }
    )
    describe("Error Cases", function() {
      describe("ERROR - New Payment Plan", function() {
        it("Reverts when user tries to create new plan with insufficient funds", async function() {
          await expect((paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.041")}))).to.be.reverted
        })
        it("Reverts when user tries to create a new plan a plan with one existing already", async function(){
          await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")})
          await expect((paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.041")}))).to.be.reverted
        })
        it("when user tries to create a new fiat plan with insufficient funds", async function(){
          await expect((paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("62")))).to.be.reverted
        })
        it("Reverts when owner tries to create a new fiat plan for a user with one existing already", async function(){
          await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"))
          await expect((paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63")))).to.be.reverted
        })
      })
      describe("ERROR - Pay Instalment", function() {
        beforeEach(async function () {
          await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
          await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"));
        })
        it("Reverts when user tries to pay instalment with insufficient funds", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await expect((paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.041")}))).to.be.reverted
        })
        it("Reverts when a user tries to pay fiat installment with insufficient funds", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await expect((paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("62")))).to.be.reverted
        })
        it("Reverts when a user tries to pay instalment when payment plan is cancelled", async function() {
          await paymentPlan.connect(addr1).cancelPlan();
          await expect((paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.042")}))).to.be.reverted
        })
        it("Reverts when a user tries to pay fiat instalment when payment plan is cancelled", async function() {
          await paymentPlan.connect(owner).fiatCancelPlan(addr2.address);
          await expect((paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("63")))).to.be.reverted
        })
        it("Reverts when a user tries to pay instalment when payment plan is completed", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.25")}); // Mock full payment
          await expect((paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.042")}))).to.be.reverted
        })
        it("Reverts when a user tries to pay fiat instalment when payment plan is completed", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("1000")); // Mock full payment
          await expect((paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("63")))).to.be.reverted
        })
        it("Reverts when a user tries to pay instalment when membership has already been claimed", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.25")}); // Mock full payment
          await paymentPlan.connect(addr1).claimMembership(addr1.address, Voucher);
          await expect((paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.042")}))).to.be.reverted
        })
        it("Reverts when a user tries to pay fiat instalment when membership has already been claimed", async function() {
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);
          await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("1000")); // Mock full payment
          await paymentPlan.connect(owner).claimMembership(addr2.address, Voucher);
          await expect((paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("63")))).to.be.reverted
        })
      })
      describe("ERROR - Claim Membership", function() {
        beforeEach(async function() {
          await paymentPlan.connect(addr1).newPlan({value: ethers.utils.parseEther("0.042")});
          await paymentPlan.connect(owner).fiatNewPlan(addr2.address, ethers.utils.parseEther("63"));
          
          await network.provider.send("evm_mine")
          await network.provider.send("evm_increaseTime", [2.678e+6]);

          // await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.25")}); // Mock full payment

          // await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("1000")); // Mock full payment
        })
        it("Reverts when a user tries to claim membership when payment plan is not completed", async function() {
          await expect((paymentPlan.connect(addr1).claimMembership(addr1.address, Voucher))).to.be.reverted
          await expect((paymentPlan.connect(owner).claimMembership(addr2.address, Voucher))).to.be.reverted
        })
        it("Reverts when a user tries to claim a membership, they have already claimed", async function() {
          await paymentPlan.connect(addr1).payInstalment({value: ethers.utils.parseEther("0.25")}); // Mock full payment
          await paymentPlan.connect(addr1).claimMembership(addr1.address, Voucher);
          await expect((paymentPlan.connect(addr1).claimMembership(addr1.address, Voucher))).to.be.reverted

          await paymentPlan.connect(owner).fiatPayment(addr2.address, ethers.utils.parseEther("1000")); // Mock full payment
          await paymentPlan.connect(owner).claimMembership(addr2.address, Voucher);
          await expect((paymentPlan.connect(owner).claimMembership(addr2.address, Voucher))).to.be.reverted
        })
      })
    })
  }
)
