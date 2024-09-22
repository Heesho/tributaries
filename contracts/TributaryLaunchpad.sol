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

    address public immutable wbera;
    ISplitter public immutable splitter;

    error Tributary__InvalidToken();

    constructor(address wbera_, address splitter_) {
        wbera = wbera_;
        splitter = ISplitter(splitter_);
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    function distribute() external {
        uint256 beraBalance = address(this).balance;
        IWBERA(wbera).deposit{value: beraBalance}();
    }

    function transferNonEth(address token_, uint256 amount_) external {
        if (token_ == wbera) revert Tributary__InvalidToken();
        IERC20(token_).safeTransfer(owner(), amount_);
    }

    /*----------  SPLITTER OWNER FUNCTIONS -----------------------------*/

    // setCreatorFee

    /*----------  TREASURY OWNER FUNCTIONS -----------------------------*/

    // withdrawFees
    // setRoyalty
    // setCreatorFee
    // setInterestRate
    // setTermLimit
    // setNoFloatValue
    // rescueERC20
    // rescueERC721

    /*----------  RECEIVE FUNCTION  ------------------------------------*/

    receive() external payable {}

}

contract TributaryLaunchpad is Ownable {

    address public constant WBERA = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8;

    address public immutable launchpad;

    address public miberaSplitter;
    mapping(address => bool) public isDerivative;

    error DerivativeFactory__ZeroAllocation();

    constructor(address launchpad_, address miberaSplitter_) {
        launchpad = launchpad_;
        miberaSplitter = miberaSplitter_;
    }

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
        isDerivative[collection_] = true;
        tributary_ = address(new Tributary(WBERA, splitter_));
        ISplitter(splitter_).transferOwnership(tributary_);
        ITreasury(treasury_).transferOwnership(tributary_);
    }

    function setMiberaSplitter(address miberaSplitter_) external onlyOwner {
        miberaSplitter = miberaSplitter_;
    }
}