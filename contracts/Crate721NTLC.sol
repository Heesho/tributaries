/*
 * SPDX-License-Identifier: UNLICENSED
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <detroitmetalcrypto@gmail.com>, JeffX <jeff@hyacinthaudits.xyz>
 * 
 * SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com> 
 */
pragma solidity 0.8.26;

import {ICrate721NTLC} from "./interface/ICrate721NTLC.sol";
import {ILaunchpad} from "./interface/ILaunchpad.sol";
import {ISplitter} from "./interface/ISplitter.sol";
import {ITreasury} from "./interface/ITreasury.sol";

import {ERC721Crate} from "@common-resources/crate/contracts/ERC721Crate.sol";
import {TransferFailed} from "@common-resources/crate/contracts/ICore.sol";

import {FixedPointMathLib as FPML} from "solady/src/utils/FixedPointMathLib.sol";
import {ERC20 as tERC20} from "token-types/src/ERC20.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";

/**
 * @title Crate721NTLC
 * @author Johannes Krauser III <detroitmetalcrypto@gmail.com>
 * @notice ERC721 Crate with treasury allocation
 */
contract Crate721NTLC is ERC721Crate, ICrate721NTLC {
    address public launchpad;
    uint16 public launchpadFee;

    uint16 public minAllocation;
    uint16 public maxAllocation;

    address public treasury;

    address public splitter;

    modifier onlyFactory() {
        if (msg.sender != launchpad) revert NotFactory();
        _;
    }

    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        string memory name_, // Collection name ("Mibera")
        string memory symbol_, // Collection symbol ("MIB")
        uint32 maxSupply_, // Max supply (~1.099T max)
        uint16 royalty_, // Percentage in basis points (420 == 4.20%)
        uint16 launchpadFee_, // Percentage going to launchpad in basis points (420 == 4.20%)
        address owner_, // Collection contract owner
        address launchpad_, // Factory contract address
        uint256 price_ // Price (~1.2M ETH max)
    )
        external
        payable
        virtual
        initializer
    {
        _initialize(name_, symbol_, maxSupply_, royalty_, owner_, price_);

        launchpad = launchpad_;
        launchpadFee = launchpadFee_;
    }

    // >>>>>>>>>>>> [ INTERNAL FUNCTIONS ] <<<<<<<<<<<<

    // >>>>>>>>>>>> [ MINT LOGIC ] <<<<<<<<<<<<

    function _handlePayments(uint256 allocation_) internal virtual {
        uint256 value = msg.value;
        if (value > 0) {
            uint256 mintAlloc;
            if (treasury != address(0) && allocation_ > 0) {
                if (allocation_ < minAllocation || allocation_ > maxAllocation) revert AllocationOutOfBounds();
                mintAlloc = FPML.fullMulDivUp(allocation_, value, _DENOMINATOR_BPS);
                payable(treasury).call{value: mintAlloc}("");
            }

            uint256 feeAlloc = FPML.fullMulDivUp(launchpadFee, value - mintAlloc, _DENOMINATOR_BPS);
            payable(launchpad).call{value: feeAlloc}("");
        }
    }

    function _handleMint(address recipient_, uint256 amount_, address referral_) internal virtual override {
        _handlePayments(minAllocation);
        ERC721Crate._handleMint(recipient_, amount_, referral_);
    }

    function _handleMintWithList(
        bytes32[] calldata proof_,
        uint8 listId_,
        address recipient_,
        uint32 amount_,
        address referral_
    )
        internal
        virtual
        override
    {
        _handlePayments(minAllocation);
        ERC721Crate._handleMintWithList(proof_, listId_, recipient_, amount_, referral_);
    }

    // Standard mint function that supports batch minting and custom allocation
    function mint(address recipient_, uint256 amount_, uint16 allocation_) public payable virtual {
        _handlePayments(allocation_);
        ERC721Crate._handleMint(recipient_, amount_, address(0));
    }

    // Standard batch mint with custom allocation support and referral fee support
    function mint(
        address recipient_,
        uint256 amount_,
        address referral_,
        uint16 allocation_
    )
        public
        payable
        virtual
        nonReentrant
    {
        _handlePayments(allocation_);
        ERC721Crate._handleMint(recipient_, amount_, referral_);
    }

    // >>>>>>>>>>>> [ PERMISSIONED / OWNER FUNCTIONS ] <<<<<<<<<<<<

    function setTreasury(
        address treasury_,
        address splitter_,
        uint16 allocation_,
        uint16 royalty_
    )
        public
        payable
        onlyFactory
    {
        treasury = treasury_;
        splitter = splitter_;

        _setAllocation(allocation_, allocation_);
        _setRoyalties(splitter, royalty_);
    }

    /**
     * @inheritdoc ERC721Crate
     * @notice Override to account for allocation when setting a percentage going to the referral
     */
    function setReferralFee(uint16 bps_) external virtual override onlyOwner {
        if (bps_ > (_DENOMINATOR_BPS - maxAllocation - launchpadFee)) revert MaxReferral();
        _setReferralFee(bps_);
    }

    function _setAllocation(uint16 min_, uint16 max_) internal virtual {
        if (treasury == address(0)) revert NoTreasury();
        if (
            (max_ < min_) // Ensure max is greater or equal than min
                || (min_ < minAllocation && _totalSupply != 0) // Ensure min is greater than current min
                || (max_ + referralFee + launchpadFee > _DENOMINATOR_BPS) // Ensure max is less than total
                || (min_ < ILaunchpad(launchpad).minAllocation()) // Ensure min is more than factory min
        ) {
            revert AllocationOutOfBounds();
        }

        minAllocation = min_;

        maxAllocation = max_;

        emit TreasuryUpdate(min_, max_);
    }

    function setAllocation(uint16 min_, uint16 max_) public virtual onlyOwner {
        _setAllocation(min_, max_);
    }

    function setRoyalties(address recipient_, uint96 bps_) external virtual override onlyOwner {
        if (bps_ > ILaunchpad(launchpad).maxMarketRoyalties()) revert MaxRoyalties();

        recipient_ = splitter == address(0) ? recipient_ : splitter;
        _setRoyalties(recipient_, bps_);
    }

    function setTokenRoyalties(uint256 tokenId_, address recipient_, uint96 bps_) external virtual override onlyOwner {
        if (bps_ > ILaunchpad(launchpad).maxMarketRoyalties()) revert MaxRoyalties();

        recipient_ = splitter == address(0) ? recipient_ : splitter;
        _setTokenRoyalties(tokenId_, recipient_, bps_);
    }

    // Withdraw non-allocated mint funds
    function withdraw(address recipient, uint256 amount) public virtual override nonReentrant {
        _withdraw(owner() == address(0) && treasury != address(0) ? treasury : recipient, amount);
    }

    // >>>>>>>>>>>> [ ASSET HANDLING ] <<<<<<<<<<<<

    // Internal handling for receive() and fallback() to reduce code length
    function _processPayment() internal virtual override {
        bool mintedOut = (_totalSupply + _reservedSupply) == maxSupply;
        if (mintedOut) {
            uint256 value = msg.value;
            if (value != 0 && treasury != address(0)) {
                // Calculate allocation and split payment accordingly
                if (owner() != address(0)) value = FPML.fullMulDivUp(maxAllocation, value, _DENOMINATOR_BPS);
                payable(treasury).call{value: value}("");
            }
            return;
        }

        if (paused()) revert EnforcedPause();

        mint(msg.sender, (msg.value / price));
    }

    /* maybe useless override since any nft that uses this contract uses onERC721Received by default */
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) public virtual override onlyOwner {
        if (token_ == address(this) && treasury != address(0)) recipient_ = treasury;
        _sendERC721(token_, recipient_, tokenId_);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external virtual returns (bytes4) {
        if (msg.sender != address(this) || treasury == address(0)) revert NoTreasury();
        _sendERC721(address(this), treasury, tokenId);
        return Crate721NTLC.onERC721Received.selector;
    }
}
