    // SPDX-License-Identifier: MIT

    pragma solidity ^0.8.9;

    import "@openzeppelin/contracts/security/Pausable.sol";
    import "@openzeppelin/contracts/access/AccessControl.sol";
    import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
    import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
    import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
    import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

    // voucher object
    struct Voucher {
        uint256 tokenId;
        uint256 stakePeriod;
        bytes signature;
    }

    // key token interface
    interface IOneClub is IERC721 {
        function getFloorWeiPrice() external view returns (uint256);

        function safeMintToPaymentPlans(address redeemer, Voucher calldata voucher) external;
        
        function transfer(address from, address to, uint256 tokenId) external;
    }

    error PaymentPlanAlreadyExists();
    error InsufficientPayment(uint256 paymentCost);
    error PaymentPlanDoesNotExist();
    error PaymentAlreadyMade();
    error PaymentPlanNotCompleted();
    error PaymentPlanExpired();
    error PaymentPlanCompleted();
    error PaymentPlanCancelled();
    error MembershipAlreadyClaimed();

    contract PaymentPlan is Pausable, AccessControl, IERC721Receiver, ReentrancyGuard {

        // State Variables
        IOneClub private oneClub;
        uint256 private gracePeriod;
        AggregatorV3Interface internal ethPriceFeed;
        uint256 private durationInMonths;
        uint256 private constant  monthsToSeconds = 2.628e6;
        address[] private members;
        
        enum PaymentStatus {NOT_STARTED, IN_PROGRESS, COMPLETED, CANCELLED}

        struct Payment {
            uint256 totalPayment;
            bool paymentInEth;
            uint256 paidAmount;
            uint256 monthlyPayment;
            uint256 firstPaymentStamp;
            uint256 lastPaymentStamp;
            PaymentStatus paymentStatus;
            bool membershipClaimed;
            uint256 tokenId;
        }

        mapping(address => Payment) public paymentPlan;

        // Roles
        bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
        bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
        bytes32 public constant FIAT_ROLE = keccak256("FIAT_ROLE");

        /* Events */

        // Emitted when a payment plan is created & when a instalment is paid
        event PaymentReceived(
            address indexed client,
            uint256 indexed amount,
            uint256 indexed timestamp,
            uint256 remainingPayment,
            uint256 monthlyPayment
        );

        // Emitted when a payment plan is expired
        event PaymentExpired(
            address indexed client,
            uint256 indexed timestamp,
            uint256 remainingPayment,
            uint256 amountPaid
        );

        // Emitted when a payment plan is completed
        event PaymentCompleted(
            address indexed client,
            uint256 indexed tokenId,
            uint256 indexed timestamp,
            uint256 totalPayment
        );

        // Emitted when a payment plan is due
        event PaymentDue(
            address indexed client,
            uint256 indexed timestamp,
            uint256 paymentAmount
        );

        // Emitted when a payment plan is cancelled
        event PaymentCancelled(
            address indexed client,
            uint256 indexed timestamp,
            uint256 remainingPayment,
            uint256 amountPaid
        );

        // Emitted when a membership is claimed
        event MembershipClaimed(
            address indexed client,
            uint256 indexed tokenId,
            uint256 indexed timestamp
        );

        constructor(
            address _oneClub,
            uint256 _gracePeriodInMonths,
            uint256 _paymentPlanDurationInMonths
        ) {
            oneClub = IOneClub(_oneClub);
            gracePeriod = _gracePeriodInMonths * monthsToSeconds;
            durationInMonths = _paymentPlanDurationInMonths;

            /**
             * Network: Goerli / Mainnet
             * Aggregator: ETH/USD
             * Address: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e / 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
             */
            ethPriceFeed = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);

            _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
            _setupRole(PAUSER_ROLE, msg.sender);
            _setupRole(MANAGER_ROLE, msg.sender);
            _setupRole(FIAT_ROLE, msg.sender);
        }

        /// @notice recieve ethereum
        receive() external payable {}

        /* Payment Plan Functions */
        
        /// @dev creates a new payment plan for user
        function newPlan() external payable whenNotPaused { 
            // check user does not have active payment plan
            if 
            (
                paymentPlan[msg.sender].paymentStatus == PaymentStatus.IN_PROGRESS  
                || 
                paymentPlan[msg.sender].paymentStatus == PaymentStatus.COMPLETED
            ){
                revert PaymentPlanAlreadyExists();
            }
            
            (uint256 totalPayment, uint256 monthlyPayment) = getPaymentPriceInEth();

            // check if user has paid enough
            if (msg.value < monthlyPayment) { 
                revert InsufficientPayment(monthlyPayment);
            }

            // add user to members array
            members.push(msg.sender);

            // initialise new payment plan
            paymentPlan[msg.sender] = Payment({
                totalPayment: totalPayment,
                paymentInEth: true,
                paidAmount: msg.value,
                monthlyPayment: monthlyPayment,
                firstPaymentStamp: block.timestamp,
                lastPaymentStamp: block.timestamp,
                paymentStatus: PaymentStatus.IN_PROGRESS,
                membershipClaimed: false,
                tokenId: 0
            });

            // emit event
            emit PaymentReceived(
                msg.sender, 
                msg.value,
                block.timestamp,
                totalPayment - msg.value,
                monthlyPayment
            );
        } 

        /// @dev allows user to make a payment
        function payInstalment() external payable whenNotPaused {
            // check if user has already created a plan
            if (paymentPlan[msg.sender].totalPayment == 0) {
                revert PaymentPlanDoesNotExist();
            }

            // check if user has already completed
            if (paymentPlan[msg.sender].paymentStatus == PaymentStatus.COMPLETED) {
                revert PaymentPlanCompleted();
            }

            // check if user has already cancelled
            if (paymentPlan[msg.sender].paymentStatus == PaymentStatus.CANCELLED) {
                revert PaymentPlanCancelled();
            }

            // check if user has already claimed membership
            if (paymentPlan[msg.sender].membershipClaimed == true) {
                revert MembershipAlreadyClaimed();
            }

            // check if user has paid enough
            if (msg.value < paymentPlan[msg.sender].monthlyPayment) {
                revert InsufficientPayment(paymentPlan[msg.sender].monthlyPayment);
            }

            // update payment plan
            paymentPlan[msg.sender].paidAmount += msg.value;
            paymentPlan[msg.sender].lastPaymentStamp = block.timestamp;
            
            // check if payment plan is complete
            if (paymentPlan[msg.sender].paidAmount >= paymentPlan[msg.sender].totalPayment) {
                paymentPlan[msg.sender].paymentStatus = PaymentStatus.COMPLETED;
                emit PaymentCompleted(
                    msg.sender,
                    paymentPlan[msg.sender].tokenId,
                    block.timestamp,
                    paymentPlan[msg.sender].totalPayment
                );
            } else {
                paymentPlan[msg.sender].paymentStatus = PaymentStatus.IN_PROGRESS;
                emit PaymentReceived(
                    msg.sender,
                    msg.value,
                    block.timestamp,
                    paymentPlan[msg.sender].totalPayment - paymentPlan[msg.sender].paidAmount,
                    paymentPlan[msg.sender].monthlyPayment
                );
            }
        }

        /// @dev allows fiat user to create payment plan
        function fiatNewPlan(address _client, uint256 _amount) external onlyRole(FIAT_ROLE) whenNotPaused {
            
            if (paymentPlan[_client].paymentStatus == PaymentStatus.IN_PROGRESS) {
                revert PaymentPlanAlreadyExists();
            }

            (uint256 totalPayment, uint256 monthlyPayment) = getPaymentPriceInFiat();

            // check if user has paid enough
            if (_amount < monthlyPayment) { 
                revert InsufficientPayment(monthlyPayment);
            }

            // create new payment plan
            paymentPlan[_client] = Payment({
                totalPayment: totalPayment,
                paymentInEth: false,
                paidAmount: _amount,
                monthlyPayment: monthlyPayment,
                firstPaymentStamp: block.timestamp,
                lastPaymentStamp: block.timestamp,
                paymentStatus: PaymentStatus.IN_PROGRESS,
                membershipClaimed: false,
                tokenId: 0 
            });

            // emit event
            emit PaymentReceived(
                _client, 
                _amount,
                block.timestamp,
                totalPayment - _amount,
                monthlyPayment
            );
        }

        ///@dev allows user to make fiat payment
        function fiatPayment(address _client, uint256 _amount) external onlyRole(MANAGER_ROLE) whenNotPaused {
            // check if user has already created a plan
            if (paymentPlan[_client].totalPayment == 0) {
                revert PaymentPlanDoesNotExist();
            }

            // check if user has already completed
            if (paymentPlan[_client].paymentStatus == PaymentStatus.COMPLETED) {
                revert PaymentPlanCompleted();
            }

            // check if user has already cancelled
            if (paymentPlan[_client].paymentStatus == PaymentStatus.CANCELLED) {
                revert PaymentPlanCancelled();
            }

            // check if user has already claimed membership
            if (paymentPlan[_client].membershipClaimed == true) {
                revert MembershipAlreadyClaimed();
            }

            // check if user has paid enough
            if (_amount < paymentPlan[_client].monthlyPayment) {
                revert InsufficientPayment(paymentPlan[_client].monthlyPayment);
            }

            // update payment plan
            paymentPlan[_client].paidAmount += _amount;
            paymentPlan[_client].lastPaymentStamp = block.timestamp;
            paymentPlan[_client].paymentStatus = PaymentStatus.IN_PROGRESS;

            // check if payment plan is complete
            if (paymentPlan[_client].paidAmount >= paymentPlan[_client].totalPayment) {
                paymentPlan[_client].paymentStatus = PaymentStatus.COMPLETED;
                emit PaymentCompleted(
                    _client,
                    paymentPlan[_client].tokenId,
                    block.timestamp,
                    paymentPlan[_client].totalPayment
                );
            } else {
                emit PaymentReceived(
                    _client, 
                    _amount,
                    block.timestamp,
                    paymentPlan[_client].totalPayment - paymentPlan[_client].paidAmount,
                    paymentPlan[msg.sender].monthlyPayment
                );
            }
        }

        /// @dev allows user to cancel payment plan
        function cancelPlan() external /* whenNotPaused ? */ {
            // check if user has already created a plan
            if (paymentPlan[msg.sender].totalPayment == 0) {
                revert PaymentPlanDoesNotExist();
            }

            // check if user has already completed
            if (paymentPlan[msg.sender].paymentStatus == PaymentStatus.COMPLETED) {
                revert PaymentPlanCompleted();
            }

            // check if user has already cancelled
            if (paymentPlan[msg.sender].paymentStatus == PaymentStatus.CANCELLED) {
                revert PaymentPlanCancelled();
            }

            // update payment plan
            paymentPlan[msg.sender].paymentStatus = PaymentStatus.CANCELLED;

            // emit event
            emit PaymentCancelled(
                msg.sender,
                block.timestamp,
                paymentPlan[msg.sender].totalPayment,
                paymentPlan[msg.sender].paidAmount
            );
        }

        function fiatCancelPlan(address _client) external onlyRole(MANAGER_ROLE) whenNotPaused {
            // check if user has already created a plan
            if (paymentPlan[_client].totalPayment == 0) {
                revert PaymentPlanDoesNotExist();
            }

            // check if user has already completed
            if (paymentPlan[_client].paymentStatus == PaymentStatus.COMPLETED) {
                revert PaymentPlanCompleted();
            }

            // check if user has already cancelled
            if (paymentPlan[_client].paymentStatus == PaymentStatus.CANCELLED) {
                revert PaymentPlanCancelled();
            }

            // update payment plan
            paymentPlan[_client].paymentStatus = PaymentStatus.CANCELLED;

            // emit event
            emit PaymentCancelled(
                _client,
                block.timestamp,
                paymentPlan[_client].totalPayment,
                paymentPlan[_client].paidAmount
            );
        }

        // @dev allows user to claim membership
        function claimMembership(address claimer, Voucher calldata voucher) external whenNotPaused {
            //check if user payment status is completed
            if (paymentPlan[claimer].paymentStatus != PaymentStatus.COMPLETED) {
                revert PaymentPlanNotCompleted();
            }

            //check if user has already claimed membership
            if (paymentPlan[claimer].membershipClaimed == true) {
                revert MembershipAlreadyClaimed();
            }

            //update payment plan
            paymentPlan[claimer].membershipClaimed = true;
            paymentPlan[claimer].tokenId = voucher.tokenId;

            //mint NFT
            oneClub.safeMint(claimer, voucher);

            //emit event
            emit MembershipClaimed(
                claimer,
                voucher.tokenId,
                block.timestamp
            );
        }

        /** View Functions */

        /// @dev returns payment plan details
        function getPaymentPlan(address _client) external view returns (Payment memory) {
            return paymentPlan[_client];
        }

        /// @dev returns price for new fiat payment plan
        function getPaymentPriceInFiat() public view returns (uint256, uint256) {
            // get current ETH price from oracle
            (
                ,
                int ethPrice,
                ,
                ,
            ) = ethPriceFeed.latestRoundData();

            // calculate total payment in USD
            uint256 totalPayment = uint256(ethPrice) * oneClub.getFloorWeiPrice() / 1e8;

            // calculate monthly payment
            uint256 monthlyPayment = totalPayment / durationInMonths;

            return (totalPayment, monthlyPayment);
        }

        /// @dev returns price for new payment plan
        function getPaymentPriceInEth() public view returns (uint256, uint256) {
            // calculate total payment in ETH
            uint256 totalPayment = oneClub.getFloorWeiPrice();

            // calculate monthly payment
            uint256 monthlyPayment = totalPayment / durationInMonths;

            return (totalPayment, monthlyPayment);
        }

        /* Admin Functions */

        function changePaymentPlanDuration(uint256 newDuration) external onlyRole(MANAGER_ROLE) {
            durationInMonths = newDuration * monthsToSeconds;
        }

        function changePriceFeed(address newPriceFeed) external onlyRole(MANAGER_ROLE) {
            ethPriceFeed = AggregatorV3Interface(newPriceFeed);
        }

        function changeOneClubAddress(address newOneClubAddress) external onlyRole(MANAGER_ROLE) {
            oneClub = IOneClub(newOneClubAddress);
        }

        function changeGracePeriod(uint256 newGracePeriod) external onlyRole(MANAGER_ROLE) {
            gracePeriod = newGracePeriod;
        }

        function getMembers() external view onlyRole(MANAGER_ROLE) returns (address[] memory) {
            return members;
        }

        function onERC721Received(
            address operator,
            address from,
            uint256 tokenId,
            bytes calldata data
        ) external pure returns (bytes4) {
            return this.onERC721Received.selector;
        }

        /// @dev allows manager to withdraw funds
        function withdraw() external onlyRole(MANAGER_ROLE) {
            (bool hs, ) = payable(msg.sender).call{value: address(this).balance}("");
            require(hs);
        }
    }