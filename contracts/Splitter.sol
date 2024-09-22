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

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20 as tERC20} from "token-types/src/ERC20.sol";

import {ILaunchpad} from "./interface/ILaunchpad.sol";
import {ITreasury} from "./interface/ITreasury.sol";
import {IWETH} from "./interface/IWETH.sol";

import {FixedPointMathLib as FPML} from "solady/src/utils/FixedPointMathLib.sol";

/**
 * @title Royalty Splitter
 * @author JeffX <jeff@hyacinthaudits.xyz>
 * @notice  Contract that handles splitting of royalties to backing and creator/ Bera Market
 */
contract RoyaltySplitter is Ownable, Initializable {
    using SafeERC20 for tERC20;

    /// EVENTS ///
    /// @notice Emitted when creator fee is updated
    event CreatorFeeUpdate(uint16 fee_);

    /// ERRORS ///

    /// @notice Error for if invalid token
    error InvalidToken();

    error InvalidFeePercent();

    /// STATE VARIABLES ///

    uint256 private constant _DENOMINATOR_BPS = 10_000;

    /// @notice Address of collection treasury
    address private TREASURY;
    /// @notice Address of bera market minter
    address private LAUNCHPAD;
    /// @notice Address of WETH
    tERC20 private WETH;

    /// @notice Percent creator receives of fees
    uint16 public CREATOR_FEE;

    /// CONSTRUCTOR ///
    constructor() {
        _disableInitializers();
    }

    /// @param owner_ Address of owner
    /// @param treasury_ Address of collection treasury
    /// @param launchpad_ Address of bera market minter
    /// @param weth_ Address of WETH
    /// @param creatorFee_ fee going to owner of splitter, in bps
    function initialize(
        address owner_,
        address treasury_,
        address launchpad_,
        address weth_,
        uint16 creatorFee_
    )
        external
        payable
        initializer
    {
        _initializeOwner(owner_);
        LAUNCHPAD = launchpad_;
        TREASURY = treasury_;
        WETH = tERC20.wrap(weth_);

        CREATOR_FEE = creatorFee_;
        emit CreatorFeeUpdate(creatorFee_);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Function that converts ETH to WETH and adds to backing / splits fees
    function sendBackingAndRoyaltyETH() public {
        uint256 total_;

        uint256 ethBalance_ = address(this).balance;
        if (ethBalance_ > 0) IWETH(tERC20.unwrap(WETH)).deposit{value: ethBalance_}();

        total_ = WETH.balanceOf(address(this));

        uint256 creatorFee_ = FPML.fullMulDivUp(CREATOR_FEE, total_, _DENOMINATOR_BPS);

        uint256 backing_ = total_ - creatorFee_;

        WETH.transfer(owner(), creatorFee_);

        WETH.approve(TREASURY, backing_);
        ITreasury(TREASURY).addToBacking(backing_);
    }

    /// OWNER FUNCTIONS ///

    /// @notice Function that transfers non ETH token to beramarket treasury and owner
    /// @param token_ Address of token to transfer
    /// @param amount_ Amount to withdraw
    function transferNonETH(address token_, uint256 amount_) external {
        tERC20 token = tERC20.wrap(token_);
        if (token == WETH) revert InvalidToken();

        token.transfer(owner(), amount_);
    }

    function setCreatorFee(uint16 bps_) external onlyOwner {
        if (bps_ > _DENOMINATOR_BPS || bps_ > ILaunchpad(LAUNCHPAD).maxSplitterCreatorFee()) {
            revert InvalidFeePercent();
        }
        CREATOR_FEE = bps_;

        emit CreatorFeeUpdate(bps_);
    }

    /// RECEIVE FUNCTION ///

    receive() external payable {}
}
