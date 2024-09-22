/*
 * SPDX-License-Identifier: UNLICENSED
 *
 * SPDX-FileType: SOURCE
 *
 * SPDX-FileCopyrightText: 2024 Johannes Krauser III <detroitmetalcrypto@gmail.com>, JeffX <jeff@hyacinthaudits.xyz>
 *
 * SPDX-FileContributor: JeffX <jeff@hyacinthaudits.xyz>
 * SPDX-FileContributor: Johannes Krauser III <detroitmetalcrypto@gmail.com>
 */
pragma solidity 0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {Initializable} from "solady/src/utils/Initializable.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import {ERC20 as tERC20} from "token-types/src/ERC20.sol";

import {ICrate721NTLC} from "./interface/ICrate721NTLC.sol";

import {ILaunchpad} from "./interface/ILaunchpad.sol";
import {ISplitter} from "./interface/ISplitter.sol";
import {ITreasury} from "./interface/ITreasury.sol";

import {ERC721 as tERC721} from "./types/tERC721.sol";

import {FixedPointMathLib as FPML} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title Launchpad
 * @author Johannes Krauser III <detroitmetalcrypto@gmail.com>
 * @author JeffX <jeff@hyacinthaudits.xyz>
 * @notice Contract that creates NFTs, treasuries, and splitters
 */
contract Launchpad is Ownable, Initializable, ILaunchpad {
    uint16 internal constant _DENOMINATOR_BPS = 10_000;

    /// @notice Address of WETH
    address public WETH;

    /// @notice Bera market fee percent
    uint16 public fee;

    // NFT STATE VARIABLES
    /// @notice Min allocation percent going to treasury
    uint16 public minAllocation;
    /// @notice Max royalty percent for secondary market sales
    uint16 public maxMarketRoyalties;
    /// @notice Default royalty percent for secondary market sales
    uint16 public defaultMarketRoyalties;

    /// SPLITTER STATE VARIABLES
    /// @notice Max creator percent for splitting secondary market royalties
    uint16 public maxSplitterCreatorFee;
    /// @notice Default creator percent for splitting secondary market royalties
    uint16 public defaultSplitterCreatorFee;

    // TREASURY STATE VARIABLES
    /// @notice Max royalty percent for treasury operations
    uint16 public maxTreasuryRoyalties;
    /// @notice Max creator percent for treasury operations
    uint16 public maxCreatorFee;
    /// @notice Max interest percent for loans
    uint16 public maxInterest;

    /// @notice Bool if approved creator
    mapping(address => bool) public approved;

    /// @notice Address of nft mastercopy
    address public nftMastercopy;
    /// @notice Mapping of nft addresses created through launchpad
    mapping(address => bool) public isDeployedNft;
    /// @notice Mapping of creator to nonce
    mapping(address => uint256) public nonce;

    /// @notice Address of treasury mastercopy
    address public treasuryMastercopy;
    /// @notice Address of splitter mastercopy
    address public splitterMastercopy;
    /// @notice Amount of treasuries created
    uint256 public created;
    /// @notice Mapping of collection to treasury and splitter
    mapping(address => uint256 index) public collectionToId;
    /// @notice Array of collection, treasury, splitter addresses
    mapping(uint256 index => address[3] collectionDetails) public collectionDetails;

    modifier onlyOwnerOrApproved(address collection_) {
        bool isNftWithOwner = _isContractOwner(collection_, msg.sender);
        /*&& tERC721.wrap(collection_).supportsInterface(0x80ac58cd)*/

        tERC721.wrap(collection_).totalSupply(); // should revert if no totalSupply function is found

        if (!isNftWithOwner && !approved[msg.sender]) revert Unauthorized();
        _;
    }

    /// CONSTRUCTOR ///
    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    /// @notice Override that returns the owner of the contract
    function owner() public view override(ILaunchpad, Ownable) returns (address) {
        return Ownable.owner();
    }

    function initialize(address weth_, uint16 fee_) public initializer onlyOwner {
        if (weth_ == address(0)) revert AddressIsZero();

        if (fee_ > _DENOMINATOR_BPS) revert InvalidFeePercent();
        WETH = weth_;

        fee = fee_;
        emit LaunchpadFeeUpdate(fee_);

        maxCreatorFee = _DENOMINATOR_BPS - fee_;
        emit CreatorFeeUpdate(maxCreatorFee);

        maxMarketRoyalties = _DENOMINATOR_BPS;
        emit MarketRoyaltiesUpdate(0, _DENOMINATOR_BPS);

        maxSplitterCreatorFee = _DENOMINATOR_BPS;
        emit SplitterCreatorFeeUpdate(0, _DENOMINATOR_BPS);

        maxTreasuryRoyalties = _DENOMINATOR_BPS;
        emit TreasuryRoyaltiesUpdate(_DENOMINATOR_BPS);

        maxInterest = _DENOMINATOR_BPS;
        emit InterestUpdate(_DENOMINATOR_BPS);
    }

    /// @notice Set the mastercopy to be cloned to create NFTs
    /// @param nftMastercopy_ Address of NFT mastercopy
    function setNftMastercopy(address nftMastercopy_) external onlyOwner {
        if (nftMastercopy_ == address(0)) revert AddressIsZero();
        nftMastercopy = nftMastercopy_;
    }

    /// @notice Set the mastercopy to be cloned to create treasuries
    /// @param treasuryMastercopy_ Address of treasury mastercopy
    function setTreasuryMastercopy(address treasuryMastercopy_) external onlyOwner {
        if (treasuryMastercopy_ == address(0)) revert AddressIsZero();
        treasuryMastercopy = treasuryMastercopy_;
    }

    /// @notice Set the mastercopy to be cloned to create splitters
    /// @param splitterMastercopy_ Address of splitter mastercopy
    function setSplitterMastercopy(address splitterMastercopy_) external onlyOwner {
        if (splitterMastercopy_ == address(0)) revert AddressIsZero();
        splitterMastercopy = splitterMastercopy_;
    }

    /// @notice Function that allows owner to set launchpad fee percent
    /// @param bps_ Fee percent
    function setLaunchpadFee(uint16 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS) revert InvalidFeePercent();

        fee = bps_;
        emit LaunchpadFeeUpdate(bps_);
    }

    function setMinAllocation(uint16 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS) revert InvalidMinAllocationPercent();

        minAllocation = bps_;
        emit MinAllocationUpdate(bps_);
    }

    /// @notice Function that allows owner to set max royalty percent
    /// @param defaultBps_ Default percent of royalties for secondary market
    /// @param maxBps_ Max percent of royalties for secondary market
    function setMarketRoyalties(uint16 defaultBps_, uint16 maxBps_) external onlyOwner {
        if (maxBps_ > _DENOMINATOR_BPS || defaultBps_ > maxBps_) revert InvalidRoyaltyPercent();

        defaultMarketRoyalties = defaultBps_;
        maxMarketRoyalties = maxBps_;

        emit MarketRoyaltiesUpdate(defaultBps_, maxBps_);
    }

    /**
     * @notice Function that allows owner to set max royalty percent for treasury operations
     * @param bps_ Max royalty percent
     */
    function setMaxTreasuryRoyalties(uint16 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS) revert InvalidRoyaltyPercent();

        maxTreasuryRoyalties = bps_;

        emit TreasuryRoyaltiesUpdate(bps_);
    }

    /// @notice Function that allows owner to set max percentage of royalties going to creator
    /// @param defaultBps_ Default percent of royalties going to creator
    /// @param maxBps_ Max percent of royalties going to creator
    function setSplitterCreatorFee(uint16 defaultBps_, uint16 maxBps_) external onlyOwner {
        if (maxBps_ > _DENOMINATOR_BPS || defaultBps_ > maxBps_) revert InvalidCreatorPercent();

        defaultSplitterCreatorFee = defaultBps_;
        maxSplitterCreatorFee = maxBps_;

        emit SplitterCreatorFeeUpdate(defaultBps_, maxBps_);
    }

    /// @notice Function that allows owner to set max creator fee
    /// @param bps_  Max creator percent
    function setMaxCreatorFee(uint16 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS) revert InvalidCreatorPercent();

        maxCreatorFee = bps_;

        emit CreatorFeeUpdate(bps_);
    }

    /// @notice Function that allows owner to set max interest percent
    /// @param bps_  Max interest percent
    function setMaxInterest(uint16 bps_) external onlyOwner {
        maxInterest = bps_;

        emit InterestUpdate(bps_);
    }

    /**
     * @notice Set or unset address as approved creator
     * @param wallet_  Address to add as creator
     * @param approved_  Bool if approved
     */
    function setApprovedCreator(address wallet_, bool approved_) external onlyOwner {
        approved[wallet_] = approved_;

        emit ApprovedCreatorUpdate(wallet_, approved_);
    }

    /**
     * @notice Function that returns the deterministic address of the NFT, given a creator and salt
     * @dev Each creator has an internal nonce that increments with each new NFT collection created
     * @param creator_ The wallet that will send the transaction to create the NFT
     * @param salt_ The salt for the deterministic address, can be left bytes32(0)
     */
    function prefetchAddress(address creator_, bytes32 salt_) public view returns (address wallet_) {
        bytes32 p = _getParameters(creator_, nonce[creator_] + 1, salt_);
        wallet_ = LibClone.predictDeterministicAddress(nftMastercopy, p, address(this));
    }

    /**
     * @dev Checks if the address has already been deployed
     * @param creator_ The wallet that will send the transaction to create the NFT
     * @param salt_ The salt for the deterministic address, can be left bytes32(0)
     */
    function _validateAddress(address creator_, bytes32 salt_) internal view {
        if (isDeployedNft[prefetchAddress(creator_, salt_)]) revert AddressAlreadySet();
    }

    /// @notice Function that creates NFT and optionally treasury and royalty splitter
    /// @param name_ Name of NFT
    /// @param symbol_ Symbol of NFT
    /// @param salt_ Salt for deterministic address
    /// @param allocation_ Mint backing percent
    /// @param creatorPercent_ Creator percent of royalty percent
    /// @param royaltyPercent_ Royalty percent
    /// @param interestRate_ Annual interest rate of loans through treasury
    /// @param mintPrice_  Mint price per NFT
    /// @param maxSupply_  Max supply of NFT
    /// @return collection_  Address of deployed collection
    /// @return treasury_  Address of deployed treasury
    /// @return splitter_  Address of deployed royalty splitter
    function createNewCollection(
        string memory name_,
        string memory symbol_,
        bytes32 salt_,
        uint16 allocation_,
        uint16 royaltyPercent_,
        uint16 creatorPercent_,
        uint16 interestRate_,
        uint256 mintPrice_,
        uint32 maxSupply_
    )
        external
        returns (address collection_, address treasury_, address splitter_)
    {
        _validateAddress(msg.sender, salt_);

        nonce[msg.sender]++;

        collection_ = LibClone.cloneDeterministic(nftMastercopy, _getParameters(msg.sender, nonce[msg.sender], salt_));
        created = created + 1;

        ICrate721NTLC(collection_).initialize(
            name_, symbol_, maxSupply_, defaultMarketRoyalties, fee, msg.sender, address(this), mintPrice_
        );

        if (allocation_ != 0) {
            if (allocation_ < minAllocation) revert InvalidAllocation();
            (treasury_, splitter_) = _createTreasury(
                msg.sender, collection_, defaultSplitterCreatorFee, creatorPercent_, royaltyPercent_, interestRate_
            );
            ICrate721NTLC(collection_).setTreasury(treasury_, splitter_, allocation_, defaultMarketRoyalties);
            emit TreasuryCreated(msg.sender, created, collection_, treasury_, splitter_, royaltyPercent_);
        }

        // Can use createTreasuryForExistingCollection later to create treasury for this collection
        isDeployedNft[collection_] = true;

        emit CollectionCreated(created, collection_, msg.sender, maxSupply_, allocation_);
        emit CreationDetails(collection_, nonce[msg.sender], salt_);

        collectionDetails[created] = [collection_, treasury_, splitter_];
        collectionToId[collection_] = created;
    }

    function createTreasuryForExistingCollection(
        address collection_,
        uint16 allocation_,
        uint16 creatorPercent_,
        uint16 royaltyPercent_,
        uint16 interestRate_
    )
        external
        onlyOwnerOrApproved(collection_)
        returns (address treasury_, address splitter_)
    {
        (treasury_, splitter_) = _createTreasury(
            msg.sender, collection_, defaultSplitterCreatorFee, creatorPercent_, royaltyPercent_, interestRate_
        );
        created = created + 1;
        collectionDetails[created] = [collection_, treasury_, splitter_];
        collectionToId[collection_] = created;

        if (isDeployedNft[collection_]) {
            ICrate721NTLC(collection_).setTreasury(treasury_, splitter_, allocation_, defaultMarketRoyalties);
        }

        emit TreasuryCreated(msg.sender, created, collection_, treasury_, splitter_, royaltyPercent_);
    }

    function _isContractOwner(address collection_, address wallet_) internal view returns (bool) {
        return tERC721.wrap(collection_).owner() == wallet_;
    }

    function _hasTreasury(address collection_) internal view returns (bool) {
        return collectionDetails[collectionToId[collection_]][1] != address(0);
    }

    function _getParameters(address creator_, uint256 nonce_, bytes32 salt_) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), creator_, nonce_, salt_));
    }

    function _getTreasuryParameters(address collection_) internal view returns (bytes32) {
        return keccak256(abi.encode(address(this), collection_));
    }

    function _createTreasury(
        address owner_,
        address collection_,
        uint16 splitterCreatorBps_,
        uint16 creatorBps_,
        uint16 royaltyBps_,
        uint16 interestBps_
    )
        internal
        returns (address treasury_, address splitter_)
    {
        if (_hasTreasury(collection_)) revert InvalidCollection();
        if (creatorBps_ > maxCreatorFee || royaltyBps_ > maxTreasuryRoyalties || interestBps_ > maxInterest) {
            revert InvalidFeePercent();
        }

        treasury_ = LibClone.cloneDeterministic(treasuryMastercopy, _getTreasuryParameters(collection_));
        ITreasury(treasury_).initialize(
            address(this), owner_, collection_, WETH, true, fee, creatorBps_, royaltyBps_, interestBps_
        );

        splitter_ = LibClone.cloneDeterministic(splitterMastercopy, _getTreasuryParameters(collection_));
        ISplitter(splitter_).initialize(collection_, treasury_, address(this), WETH, splitterCreatorBps_);
    }

    function withdraw(address recipient_) external onlyOwner {
        payable(recipient_).transfer(address(this).balance);
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
        _sendERC20(token, recipient_, balance);
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
        _sendERC721(tERC721.wrap(token_), recipient_, tokenId_);
    }

    receive() external payable {}
}
