// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ILaunchpad {
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
        returns (address collection_, address treasury_, address splitter_);
}

interface ISplitter {
    function transferOwnership(address newOwner) external;
    function setCreatorFee(uint16 bps_) external; 
}

interface ITreasury {
    function transferOwnership(address newOwner) external;
    function withdrawFees() external;
    function setRoyalty(uint256 bps_) external;
    function setCreatorFee(uint256 bps_) external;
    function setInterestRate(uint256 bps_) external;
    function setTermLimit(uint256 termLimit_) external;
    function setNoFloatValue(uint256 value_) external;
    function rescueERC20(address token_, address recipient_) external;
    function rescueERC721(address token_, address recipient_, uint256 tokenId_) external;
}

interface IWBERA {
    function deposit() external payable;
}

contract Tributary is Ownable {
    using SafeERC20 for IERC20;

    /// STATE VARIABLES ///

    address public immutable wbera; // address of wbera token   
    address public immutable tributaryLaunchpad; // address of tributary launchpad
    address public immutable splitter; // address of collection splitter
    address public immutable treasury; // address of collection treasury

    /// EVENTS ///

    event Tributary__Distribute(uint256 beraBalance);
    event Tributary__RescueERC20(address token_, uint256 amount_);

    /// ERRORS ///

    error Tributary__NotOwner();
    error Tributary__InvalidToken();

    /// PUBLIC FUNCTIONS ///

    /// @notice Constructor for tributary contract
    /// @param wbera_ Address of wbera token
    /// @param tributaryLaunchpad_ Address of tributary launchpad
    /// @param splitter_ Address of splitter contract
    constructor(address wbera_, address tributaryLaunchpad_, address splitter_, address treasury_) {
        wbera = wbera_;
        tributaryLaunchpad = tributaryLaunchpad_;
        splitter = splitter_;
        treasury = treasury_;
    }

    /// @notice Function that distributes wbera to owner and mibera splitter
    function distribute() external {
        uint256 beraBalance = address(this).balance;
        IWBERA(wbera).deposit{value: beraBalance}();
        IERC20(wbera).safeTransfer(owner(), beraBalance / 2);
        IERC20(wbera).safeTransfer(TributaryLaunchpad(tributaryLaunchpad).miberaSplitter(), beraBalance / 2);
        emit Tributary__Distribute(beraBalance);
    }

    /// RESTRICTED FUNCTIONS ///

    /// @notice Function that rescues ERC20 tokens from tributary contract
    /// @param token_ Address of token to rescue
    /// @param amount_ Amount of token to rescue
    function rescueERC20(address token_, uint256 amount_) external onlyOwner {
        if (token_ == wbera) revert Tributary__InvalidToken();
        IERC20(token_).safeTransfer(owner(), amount_);
        emit Tributary__RescueERC20(token_, amount_);
    }

    /// SPLITTER OWNER FUNCTIONS ///

    /// @notice Set new creator fee on splitter
    /// @param bps_ New creator fee
    function setCreatorFeeSplitter(uint16 bps_) external onlyOwner {
        ISplitter(splitter).setCreatorFee(bps_);
    }

    /// TREASURY OWNER FUNCTIONS ///

    /// @notice  Function sends accumulated fees in treasury to this contract and bera market treasury
    function withdrawFeesFromTreasury() external {
        if (msg.sender != owner() || msg.sender != TributaryLaunchpad(tributaryLaunchpad).owner()) revert Tributary__NotOwner();
        ITreasury(treasury).withdrawFees();
    }

    /// @notice Set new royalty percent on treasury
    /// @param bps_ New royalty percent
    function setRoyalty(uint256 bps_) external onlyOwner {
        ITreasury(treasury).setRoyalty(bps_);
    }
    
    /// @notice Set new creator fee on treasury
    /// @param bps_ New creator fee
    function setCreatorFeeTreasury(uint256 bps_) external onlyOwner {
        ITreasury(treasury).setCreatorFee(bps_);
    }

    /// @notice Set new interest rate on treasury
    /// @param bps_ New interest rate
    function setInterestRateTreasury(uint256 bps_) external onlyOwner {
        ITreasury(treasury).setInterestRate(bps_);
    }

    /// @notice Set max term limit for loans
    /// @param termLimit_ Max term limit on a loan
    function setTermLimit(uint256 termLimit_) external onlyOwner {
        ITreasury(treasury).setTermLimit(termLimit_);
    }

    /// @notice  Function that sets purchase price if float is 0 on treasury
    /// @param value_ New no float value
    function setNoFloatValue(uint256 value_) external onlyOwner {
        ITreasury(treasury).setNoFloatValue(value_);
    }

    /// @notice Rescue ERC20 from treasury
    /// @param token_ Address of token to rescue
    /// @param recipient_ Address of recipient
    function rescueERC20FromTreasury(address token_, address recipient_) external onlyOwner {
        ITreasury(treasury).rescueERC20(token_, recipient_);
    }

    /// @notice Rescue ERC721 from treasury
    /// @param token_ Address of token to rescue
    /// @param recipient_ Address of recipient
    /// @param tokenId_ Token ID of ERC721 to rescue
    function rescueERC721FromTreasury(address token_, address recipient_, uint256 tokenId_) external onlyOwner {
        ITreasury(treasury).rescueERC721(token_, recipient_, tokenId_);
    }

    /// RECEIVE FUNCTION ///

    receive() external payable {}

}

contract TributaryLaunchpad is Ownable {

    /// STATE VARIABLES ///

    address public immutable wbera; // address of wbera token
    address public immutable launchpad; // address of launchpad
    address public miberaSplitter; // address of mibera splitter

    struct Collection {
        address collection;
        address treasury;
        address splitter;
        address tributary;
    }

    uint256 index = 0; // index for collection
    mapping(uint256 => Collection) public collections; // index => collection
    mapping(address => bool) public isDerivative; // collection address => is derivative

    /// EVENTS ///

    event TributaryLaunchpad__CreateDerivativeCollection(address collection_, address treasury_, address splitter_, address tributary_);
    event TributaryLaunchpad__SetMiberaSplitter(address miberaSplitter_);

    /// ERRORS ///

    error DerivativeFactory__ZeroAllocation();

    /// PUBLIC FUNCTIONS ///

    /// @notice Constructor for tributary launchpad
    /// @param wbera_ Address of wbera token
    /// @param launchpad_ Address of launchpad
    /// @param miberaSplitter_ Address of mibera splitter
    constructor(address wbera_, address launchpad_, address miberaSplitter_) {
        wbera = wbera_;
        launchpad = launchpad_;
        miberaSplitter = miberaSplitter_;
    }

    /// @notice Function that creates a new mibera derivative collection on the launchpad 
    /// and sets the tributary contract as the owner of the splitter, treasury, and transfers
    /// ownership of the tributary contract to the creator of the collection
    /// @param name_ Name of the collection
    /// @param symbol_ Symbol of the collection
    /// @param salt_ Salt for the collection
    /// @param allocation_ Allocation for the collection
    /// @param royaltyPercent_ Royalty percent for the collection
    /// @param creatorPercent_ Creator percent for the collection   
    /// @param interestRate_ Interest rate for the collection
    /// @param mintPrice_ Mint price for the collection
    function createDerivativeCollection(
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
        returns (address collection_, address treasury_, address splitter_, address tributary_) 
    {
        if  (allocation_ != 0) revert DerivativeFactory__ZeroAllocation();
        (collection_, treasury_, splitter_) = ILaunchpad(launchpad).createNewCollection(
            name_,
            symbol_,
            salt_,
            allocation_,
            royaltyPercent_,
            creatorPercent_,
            interestRate_,
            mintPrice_,
            maxSupply_
        );
        tributary_ = address(new Tributary(wbera, address(this), splitter_, treasury_));

        collections[index].collection = collection_;
        collections[index].treasury = treasury_;
        collections[index].splitter = splitter_;
        collections[index].tributary = tributary_;
        index++;
        isDerivative[collection_] = true;

        Tributary(payable(tributary_)).transferOwnership(msg.sender);
        ISplitter(splitter_).transferOwnership(tributary_);
        ITreasury(treasury_).transferOwnership(tributary_);
        
        emit TributaryLaunchpad__CreateDerivativeCollection(collection_, treasury_, splitter_, tributary_);
    }

    /// RESTRICTED FUNCTIONS ///

    /// @notice Function that sets the mibera splitter address
    /// @param miberaSplitter_ Address of the mibera splitter
    function setMiberaSplitter(address miberaSplitter_) external onlyOwner {
        miberaSplitter = miberaSplitter_;
        emit TributaryLaunchpad__SetMiberaSplitter(miberaSplitter_);
    }
}