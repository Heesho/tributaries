pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ISplitter {

}

contract Tributary is Ownable {

    ISplitter public immutable splitter;

    constructor(address splitter_) {
        splitter = ISplitter(splitter_);
    }

}

contract TributaryFactory is Ownable {

    address public immutable launchpad;

    constructor() {}

    function createTributary(
        address splitter_
    ) 
        external 
        returns (address tributary_) 
    {
        tributary_ = address(new Tributary(splitter_));
    }
}