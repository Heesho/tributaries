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

contract DerivativeFactory is Ownable {

    address public immutable launchpad;

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
        // create collection through launchpad
        // create tributary through tributary factory
        // transfer ownership of splitter to tributary
    }
}