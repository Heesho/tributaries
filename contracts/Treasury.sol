/*
 * SPDX-License-Identifier: UNLICENSED
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 JeffX <jeff@hyacinthaudits.xyz>
 * 
 * SPDX-FileContributor: JeffX <jeff@hyacinthaudits.xyz> 
 * SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com> 
 */
pragma solidity 0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";

import {ILaunchpad} from "./interface/ILaunchpad.sol";
import {ITreasury} from "./interface/ITreasury.sol";
import {IWETH} from "./interface/IWETH.sol";

import {ERC721 as tERC721} from "./types/tERC721.sol";
import {ERC20 as tERC20} from "token-types/src/ERC20.sol";

import {FixedPointMathLib as FPML} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title Royalty Splitter
 * @author JeffX <jeff@hyacinthaudits.xyz>
 * @notice  Individual Treasury a collection will deploy
 */
contract Treasury is Ownable, Initializable, ITreasury {
    /// STATE VARIABLES ///

    /// @notice One year in seconds
    uint256 private constant _ONE_YEAR = 31_536_000;

    /// @notice 100% with 2 decimal places
    uint256 private constant _DENOMINATOR_BPS = 10_000;

    /// @notice Current backing loan id
    uint256 public backingLoanId;
    /// @notice Current item loan id
    uint256 public itemLoanId;

    /// @notice Value to sell first NFT if float is 0
    uint256 public noFloatValue;

    /// @notice Address of collection
    tERC721 private collection;

    /// @notice Address of Collateral
    tERC20 private collateral;
    /// @notice whether or not collateral is WETH
    bool private isWeth;

    /// @notice Address of Bera market minter
    address private LAUNCHPAD;

    /// @notice Bera market fee percent
    uint256 public LAUNCHPAD_FEE;

    /// @notice Fee percent for purchasing or redeeming through treasury
    uint256 public royalty;

    /// @notice Percent creator receives of fees
    uint256 public creatorFee;

    /// @notice Interest rate on loans
    uint256 public interest;

    /// @notice Max term limit on loan
    uint256 public termLimit;

    /// @notice Current fees that creator can withdraw
    uint256 public feesToWithdraw;

    /// @notice Current backing of the treasury
    uint256 public backing;
    /// @notice Amount of backing that is loaned out from treasury
    uint256 public backingLoanedOut;

    /// @notice Amount of collateral held by the treasury
    uint256 public collateralHeld;

    /// @notice Number of items treasury owns
    uint256 public itemsTreasuryOwns;

    /// @notice Details of backing loan of id
    mapping(uint256 id => BackingLoan backingLoan) public backingLoanDetails;
    /// @notice Bool if loan is on item id
    mapping(uint256 id => uint256 loanId) public loanOnItem;

    /// @notice Details of item loan of id
    mapping(uint256 id => ItemLoan itemLoan) public itemLoanDetails;
    /// @notice Bool if item id has been loaned from treasury
    mapping(uint256 id => uint256 loanId) public itemLoaned;

    /// @notice Bool if item id is treasury owned
    mapping(uint256 id => bool isTreasuryOwned) public treasuryOwned;

    /// CONSTRUCTOR ///
    constructor() {
        _disableInitializers();
    }

    /// @param launchpad_ Address of bera market minter contract
    /// @param owner_ Address of the treasury owner
    /// @param collection_ Address of the collection
    /// @param collateral_ Address of the collateral
    /// @param isWeth_ Whether or not collateral is WETH
    /// @param launchpadBps_ Launchpad fee percent
    /// @param creatorBps_ Percent of royalty that goes to creator
    /// @param royaltyBps_ Royalty percent
    /// @param interestBps_ Annual interest rate for loans
    function initialize(
        address launchpad_,
        address owner_,
        address collection_,
        address collateral_,
        bool isWeth_,
        uint256 launchpadBps_,
        uint256 creatorBps_,
        uint256 royaltyBps_,
        uint256 interestBps_
    )
        external
        payable
        initializer
    {
        _initializeOwner(owner_);

        ++backingLoanId;
        ++itemLoanId;

        collection = tERC721.wrap(collection_);

        collateral = tERC20.wrap(collateral_);
        isWeth = isWeth_;

        LAUNCHPAD = launchpad_;
        LAUNCHPAD_FEE = launchpadBps_;

        creatorFee = creatorBps_;
        emit CreatorFeeUpdate(creatorBps_);

        royalty = royaltyBps_;
        emit RoyaltyUpdate(royaltyBps_);

        interest = interestBps_;
        emit InterestRateUpdate(interestBps_);
    }

    /// OWNER FUNCTIONS ///

    /// @notice Set new royalty percent
    /// @param bps_ New royalty percent
    function setRoyalty(uint256 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS || bps_ > ILaunchpad(LAUNCHPAD).maxTreasuryRoyalties()) {
            revert RoyaltyOutOfBounds();
        }
        royalty = bps_;

        emit RoyaltyUpdate(bps_);
    }

    /// @notice Set new creator fee
    /// @param bps_ New creator fee
    function setCreatorFee(uint256 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS - LAUNCHPAD_FEE || bps_ > ILaunchpad(LAUNCHPAD).maxCreatorFee()) {
            revert CreatorFeeOutOfBounds();
        }
        creatorFee = bps_;

        emit CreatorFeeUpdate(bps_);
    }

    /// @notice Set new interest rate
    /// @param bps_ New interest rate
    function setInterestRate(uint256 bps_) external onlyOwner {
        if (bps_ > ILaunchpad(LAUNCHPAD).maxInterest()) revert InterestOutOfBounds();
        interest = bps_;

        emit InterestRateUpdate(bps_);
    }

    /// @notice Set max term limit for loans
    /// @param termLimit_ Max term limit on a loan
    function setTermLimit(uint256 termLimit_) external onlyOwner {
        termLimit = termLimit_;

        emit TermLimitUpdate(termLimit_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice         Function that adds wETH to backing
    /// @param amount_  Amount of wETH to add to backing
    function addToBacking(uint256 amount_) external {
        if (amount_ == 0) revert InvalidInput();
        backing += amount_;
        collateral.transferFrom(msg.sender, address(this), amount_);

        emit BackingAdded(amount_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice       Function that redeems item to treasury to receive backing
    /// @param id_    Item id to redeem
    function redeemItem(uint256 id_) external {
        if (isLoaned(id_) || treasuryOwned[id_]) revert NotOwner();

        uint256 rfv_ = realFloorValue();
        uint256 creatorFee_;

        uint256 fee_ = (royalty * rfv_) / 100;
        creatorFee_ = (creatorFee * fee_) / 100;
        feesToWithdraw += creatorFee_;
        uint256 toReceive_ = rfv_ - fee_;

        backing -= (toReceive_ + creatorFee_);

        ++itemsTreasuryOwns;

        treasuryOwned[id_] = true;

        collection.transferFrom(msg.sender, address(this), id_);
        collateral.transfer(msg.sender, toReceive_);

        emit ItemRedeemed(id_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice       Function that purchases item from treasury
    /// @param id_    Item id to purchase
    function purchaseItem(uint256 id_) external {
        if (float() == 0 && noFloatValue == 0) revert NoFloatValueZero();
        if (hasLoan(id_) || !treasuryOwned[id_]) revert NotTreasuryOwned();

        uint256 rfv_ = realFloorValue();
        uint256 fee_ = FPML.fullMulDivUp(royalty, rfv_, _DENOMINATOR_BPS);
        uint256 toPay_ = rfv_ + fee_;
        uint256 creatorFee_ = FPML.fullMulDivUp(creatorFee, fee_, _DENOMINATOR_BPS);
        uint256 launchpadFee = FPML.fullMulDivUp(LAUNCHPAD_FEE, fee_, _DENOMINATOR_BPS);

        feesToWithdraw = feesToWithdraw + creatorFee_ + launchpadFee;
        backing += backing + toPay_ - creatorFee_ - launchpadFee;

        --itemsTreasuryOwns;

        treasuryOwned[id_] = false;

        collateral.transferFrom(msg.sender, address(this), toPay_);
        collection.transferFrom(address(this), msg.sender, id_);

        emit ItemPurchased(id_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice           Function that allows user to receive a loan on backing of `id_`
    /// @param id_        Array of items to use as collateral
    /// @param amount_    Amount of wETH to receive for loan
    /// @param duration_  Duration loan will be active
    function receiveLoan(uint256[] calldata id_, uint256 amount_, uint256 duration_) external {
        if (id_.length == 0 || amount_ == 0 || duration_ == 0 || duration_ > termLimit) revert InvalidInput();
        uint256 rfv_ = realFloorValue();
        uint256 totalBacking_ = rfv_ * id_.length;
        uint256 totalAccessible_ = FPML.fullMulDivUp((_DENOMINATOR_BPS - royalty), totalBacking_, _DENOMINATOR_BPS);
        uint256 interest_ = (duration_ * amount_ * interest) / _ONE_YEAR / 10_000;
        uint256 totalOwed_ = amount_ + interest_;

        uint256 length = id_.length;
        for (uint256 i; i < length; ++i) {
            uint256 id = id_[i];
            if (isLoaned(id) || treasuryOwned[id]) revert NotOwner();
            loanOnItem[id] = backingLoanId;
            collection.transferFrom(msg.sender, address(this), id);
        }

        if (totalOwed_ > totalAccessible_) revert NotEnoughValue();

        uint256 _loanId = backingLoanId;
        BackingLoan storage loan = backingLoanDetails[_loanId];
        ++backingLoanId;

        loan.loanedTo = msg.sender;
        loan.ids = id_;
        loan.timestampDue = block.timestamp + duration_;
        loan.interestOwed = interest_;
        loan.backingOwed = amount_;
        loan.defaultCreatorFee = ((creatorFee) * (totalBacking_ - totalAccessible_)) / 100;

        backing -= amount_;
        backingLoanedOut += amount_;

        collateral.transfer(msg.sender, amount_);

        emit LoanReceived(_loanId, id_, amount_, loan.timestampDue);
    }

    /// @notice         Function that adjusts backing if loan expired
    /// @param loanId_  Loan id that has expired
    function backingLoanExpired(uint256 loanId_) external {
        BackingLoan memory loan = backingLoanDetails[loanId_];
        delete backingLoanDetails[loanId_];
        if (loan.timestampDue == 0) revert InvalidLoanId();
        if (block.timestamp <= loan.timestampDue) revert ActiveLoan();

        for (uint256 i; i < loan.ids.length; ++i) {
            loanOnItem[loan.ids[i]] = 0;
            treasuryOwned[loan.ids[i]] = true;
        }

        backingLoanedOut -= loan.backingOwed;
        itemsTreasuryOwns += loan.ids.length;

        loan.defaultCreatorFee = loan.defaultCreatorFee > backing ? backing : loan.defaultCreatorFee;
        feesToWithdraw += loan.defaultCreatorFee;
        backing -= loan.defaultCreatorFee;

        emit BackingLoanExpired(loanId_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice         Function that pays `loanId_` back
    /// @param loanId_  Loan id to pay back for
    /// @param amount_  Amount paying back
    function payLoanBack(uint256 loanId_, uint256 amount_) external {
        if (amount_ == 0) revert InvalidInput();
        BackingLoan memory loan = backingLoanDetails[loanId_];

        if (block.timestamp > loan.timestampDue) revert InactiveLoan();

        uint256 totalOwed_ = loan.interestOwed + loan.backingOwed;
        if (amount_ > totalOwed_) revert InvalidAmount();

        collateral.transferFrom(msg.sender, address(this), amount_);

        uint256 toBacking_ = amount_;
        uint256 creatorFee_;
        if (amount_ == totalOwed_) {
            delete backingLoanDetails[loanId_];
            creatorFee_ = (creatorFee * loan.interestOwed) / 100;
            feesToWithdraw += creatorFee_;
            toBacking_ = totalOwed_ - creatorFee_;
            backing += toBacking_;
            backingLoanedOut -= loan.backingOwed;
            for (uint256 i; i < loan.ids.length; ++i) {
                loanOnItem[loan.ids[i]] = 0;
                collection.transferFrom(address(this), loan.loanedTo, loan.ids[i]);
            }

            emit BackingLoanPayedBack(loanId_, backing);
            emit RFVChanged(realFloorValue());

            return;
        }

        if (loan.interestOwed > 0) {
            if (amount_ > loan.interestOwed) {
                creatorFee_ = (creatorFee * loan.interestOwed) / 100;
                backingLoanDetails[loanId_].interestOwed = 0;
                feesToWithdraw += creatorFee_;
                toBacking_ -= creatorFee_;
                amount_ -= loan.interestOwed;
                emit RFVChanged(realFloorValue());
            } else {
                creatorFee_ = (creatorFee * amount_) / 100;
                feesToWithdraw += creatorFee_;
                toBacking_ -= creatorFee_;
                backingLoanDetails[loanId_].interestOwed -= amount_;
                backing += toBacking_;
                emit RFVChanged(realFloorValue());
                return;
            }
        }

        backing += toBacking_;
        backingLoanedOut -= amount_;
        backingLoanDetails[loanId_].backingOwed -= amount_;
    }

    /// @notice           Function that loan `id_` from treasury
    /// @param id_        Id of item of loan
    /// @param duration_  Duration loan will be active
    function loanItem(uint256 id_, uint256 duration_) external {
        if (duration_ == 0 || duration_ > termLimit) revert InvalidInput();
        if (hasLoan(id_) || isLoaned(id_) || !treasuryOwned[id_]) revert NotTreasuryOwned();
        if (float() == 0 && noFloatValue == 0) revert NoFloatValueZero();

        uint256 rfv_ = realFloorValue();
        uint256 fee_ = (royalty * rfv_) / 100;
        uint256 cost_ = rfv_ + fee_;
        uint256 interest_ = (duration_ * cost_ * interest) / _ONE_YEAR / 10_000;
        uint256 costWithInterest_ = cost_ + interest_;

        uint256 _loanId = itemLoanId;
        ItemLoan storage loan = itemLoanDetails[_loanId];
        itemLoaned[id_] = _loanId;
        ++itemLoanId;

        loan.tokenId = id_;
        loan.timestampDue = block.timestamp + duration_;
        loan.collateralGiven = cost_;
        loan.paidBackCreatorFee = (creatorFee * interest_) / 100;
        loan.defaultCreatorFee = (creatorFee * fee_) / 100;

        backing += costWithInterest_;
        collateralHeld += cost_;

        collateral.transferFrom(msg.sender, address(this), costWithInterest_);
        collection.transferFrom(address(this), msg.sender, id_);

        emit ItemLoaned(_loanId, id_, loan.timestampDue);
        emit RFVChanged(realFloorValue());
    }

    /// @notice         Function that transfers loaned item back to treasury
    /// @param loanId_  Loan id to send item back for
    function sendLoanedItemBack(uint256 loanId_, address recipient_) public {
        ItemLoan memory loan = itemLoanDetails[loanId_];
        delete itemLoanDetails[loanId_];

        if (block.timestamp > loan.timestampDue) revert InactiveLoan();

        collection.transferFrom(msg.sender, address(this), loan.tokenId);

        backing -= loan.collateralGiven;
        collateralHeld -= loan.collateralGiven;

        loan.paidBackCreatorFee = loan.paidBackCreatorFee > backing ? backing : loan.paidBackCreatorFee;
        feesToWithdraw += loan.paidBackCreatorFee;

        backing -= loan.paidBackCreatorFee;

        itemLoaned[loan.tokenId] = 0;

        collateral.transfer(recipient_, loan.collateralGiven);

        emit LoanItemSentBack(loanId_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice         Function that adjust backing if item loan has expired
    /// @param loanId_  Id of of item loan that has expired
    function itemLoanExpired(uint256 loanId_) public {
        ItemLoan memory loan = itemLoanDetails[loanId_];
        delete itemLoanDetails[loanId_];
        if (loan.timestampDue == 0) revert InvalidLoanId();
        if (block.timestamp <= loan.timestampDue) revert ActiveLoan();

        itemLoaned[loan.tokenId] = 0;
        --itemsTreasuryOwns;
        collateralHeld -= loan.collateralGiven;

        loan.defaultCreatorFee = loan.defaultCreatorFee > backing ? backing : loan.defaultCreatorFee;
        feesToWithdraw += loan.defaultCreatorFee;
        backing -= loan.defaultCreatorFee;
        treasuryOwned[loan.tokenId] = false;

        emit ItemLoanExpired(loanId_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// EXTERNAL VIEW FUNCTIONS ///

    /// @notice         Function that returns RFV of items in collection
    /// @return value_  RFV of item in collection
    function realFloorValue() public view returns (uint256 value_) {
        uint256 backing_ = backing;
        uint256 backingLoanedOut_ = backingLoanedOut;
        uint256 collateralHeld_ = collateralHeld;
        uint256 float_ = float();

        if (float_ > 0) value_ = (backing_ + backingLoanedOut_ - collateralHeld_) / float_;
        else value_ = (backing_ + backingLoanedOut_ - collateralHeld_) + noFloatValue;
    }

    /// @notice Function that returns float of collection
    /// @return float_ Number of supply not treasury owned
    function float() public view returns (uint256 float_) {
        float_ = collection.totalSupply() - itemsTreasuryOwns;
    }

    function hasLoan(uint256 id_) public view returns (bool) {
        return loanOnItem[id_] != 0;
    }

    function isLoaned(uint256 id_) public view returns (bool) {
        return itemLoaned[id_] != 0;
    }

    /// OWNER FUNCTIONS ///

    /// @notice  Function sends accumulated fees to owner and bera market treasury
    function withdrawFees() external {
        if (msg.sender != owner() || msg.sender != ILaunchpad(LAUNCHPAD).owner()) revert NotOwner();
        uint256 total_ = feesToWithdraw;

        feesToWithdraw = 0;
        uint256 beraMarketFee_ = (total_ * LAUNCHPAD_FEE) / 100;
        uint256 remainingHarvest_ = total_ - beraMarketFee_;

        collateral.transfer(LAUNCHPAD, beraMarketFee_);
        collateral.transfer(owner(), remainingHarvest_);
    }

    /// @notice  Function that sets purchase price if float is 0
    function setNoFloatValue(uint256 value_) external onlyOwner {
        if (value_ == 0) revert NoFloatValueZero();
        noFloatValue = value_;

        emit RFVChanged(realFloorValue());
    }

    function _sendERC20(tERC20 token_, address recipient_, uint256 amount_) internal virtual {
        token_.transfer(recipient_, amount_);
    }

    /**
     * @dev function to retrieve erc20 from the contract
     * @param token_ The address of the ERC20 token.
     * @param recipient_ The address to which the tokens are transferred.
     */
    function rescueERC20(address token_, address recipient_) external onlyOwner {
        tERC20 token = tERC20.wrap(token_);
        uint256 balance = token.balanceOf(address(this));
        if (token != collateral) {
            _sendERC20(token, recipient_, balance);
        }

        _handleUnexpectedBacking(balance);
    }

    function _sendERC721(tERC721 token_, address recipient_, uint256 tokenId_) internal virtual {
        token_.safeTransferFrom(address(this), recipient_, tokenId_, "");
    }

    /**
     * @notice Rescue ERC721 tokens from the contract.
     * @param token_ The address of the ERC721 to retrieve.
     * @param recipient_ The address to which the token is transferred.
     * @param tokenId_ The ID of the token to be transferred.
     */
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) external onlyOwner {
        if (tERC721.wrap(token_) != collection) {
            _sendERC721(tERC721.wrap(token_), recipient_, tokenId_);
            return;
        }
        _handleUnexpectedNFT(recipient_, tokenId_);
    }

    /// RECEIVE ///
    function onERC721Received(
        address,
        address from_,
        uint256 tokenId_,
        bytes calldata
    )
        external
        virtual
        returns (bytes4)
    {
        if (tERC721.wrap(msg.sender) != collection) revert NoCollection();

        _handleUnexpectedNFT(from_, tokenId_);
        return Treasury.onERC721Received.selector;
    }

    function _handleUnexpectedNFT(address from_, uint256 tokenId_) internal {
        uint256 loanId = itemLoaned[tokenId_];
        if (loanId != 0) {
            ItemLoan memory loan = itemLoanDetails[loanId];
            if (block.timestamp > loan.timestampDue) {
                itemLoanExpired(loanId);
            } else {
                sendLoanedItemBack(loanId, from_);
                return;
            }
        }
        // handle itemTreasuryOwns here
        ++itemsTreasuryOwns;
        treasuryOwned[tokenId_] = true;

        emit ItemReceived(tokenId_, backing);
        emit RFVChanged(realFloorValue());
    }

    function _handleUnexpectedBacking(uint256 value_) internal {
        backing += value_;

        emit BackingAdded(value_, backing);
        emit RFVChanged(realFloorValue());
    }

    /// @notice  Deposit and add to backing
    receive() external payable {
        if (isWeth) {
            uint256 value_ = msg.value;
            address collateralAddress = tERC20.unwrap(collateral);
            IWETH(collateralAddress).deposit{value: value_}();

            _handleUnexpectedBacking(value_);
        }
    }
}
