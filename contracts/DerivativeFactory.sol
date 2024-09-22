pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

contract Tributary is Ownable {

    ISplitter public immutable splitter;

    constructor(address splitter_) {
        splitter = ISplitter(splitter_);
    }

    function setCreatorFee(uint16 bps_) external onlyOwner {
        ISplitter(splitter).setCreatorFee(bps_);
    }

    // transferNonEth

    // distribute to owner and mibera treasury

}

contract DerivativeFactory is Ownable {

    address public immutable launchpad;
    mapping(address => bool) public isDerivative;

    constructor(address launchpad_) {
        launchpad = launchpad_;
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
        tributary_ = address(new Tributary(splitter_));
        ISplitter(splitter_).transferOwnership(tributary_);
    }
}