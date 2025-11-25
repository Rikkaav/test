// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/STBL_YLD.sol";
import "../src/STBL_Structs.sol";
import "../src/STBL_Errors.sol";

contract SimpleProxy {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    constructor(address implementation, bytes memory initData) {
        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation)
        }
        if (initData.length > 0) {
            (bool success, ) = implementation.delegatecall(initData);
            require(success, "Initialization failed");
        }
    }
    
    fallback() external payable {
        assembly {
            let impl := sload(IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
    
    receive() external payable {}
}

contract STBL_YLD_TokenURIBugTest is Test {
    STBL_YLD public yldContract;
    
    address public admin;
    address public minter;
    address public user;
    
    string constant BASE_URI = "https://api.stbl.finance/metadata/";
    
    function setUp() public {
        // Setup addresses
        admin = address(this);
        minter = makeAddr("minter");
        user = makeAddr("user");
        
        // Deploy implementation contract
        STBL_YLD implementation = new STBL_YLD();
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            STBL_YLD.initialize.selector,
            BASE_URI
        );
        
        // Deploy proxy and initialize
        SimpleProxy proxy = new SimpleProxy(
            address(implementation),
            initData
        );
        
        // Wrap proxy with STBL_YLD interface
        yldContract = STBL_YLD(address(proxy));
        
        // Grant MINTER_ROLE to minter address
        yldContract.grantRole(yldContract.MINTER_ROLE(), minter);
    }
    
    // Helper function to create default metadata
    function _createDefaultMetadata() internal view returns (YLD_Metadata memory) {
        FeeStruct memory defaultFees = FeeStruct({
            depositFee: 0,
            hairCut: 0,
            withdrawFee: 0,
            insuranceFee: 0,
            duration: 0,
            yieldDuration: 0
        });
        
        return YLD_Metadata({
            assetID: 1,
            uri: "",
            assetValue: 1000 ether,
            stableValueGross: 1000 ether,
            stableValueNet: 950 ether,
            depositTimestamp: block.timestamp,
            depositfeeAmount: 10 ether,
            haircutAmount: 40 ether,
            haircutAmountAssetValue: 40 ether,
            withdrawfeeAmount: 5 ether,
            insurancefeeAmount: 5 ether,
            Fees: defaultFees,
            additionalBuffer: "",
            isDisabled: false
        });
    }

    function test_BrokenTokenURI() public {
        // Mint NFT
        vm.prank(minter);
        uint256 tokenId = yldContract.mint(user, _createDefaultMetadata());
        
        // Get actual vs expected URI
        string memory actualURI = yldContract.tokenURI(tokenId);
        string memory expectedURI = string(abi.encodePacked(BASE_URI, vm.toString(tokenId)));
        
        // Log results
        console.log("Expected:", expectedURI);
        console.log("Expected length:", bytes(expectedURI).length);
        console.log("Actual length:", bytes(actualURI).length);
        console.log("Extra bytes:", bytes(actualURI).length - bytes(expectedURI).length);
        console.logBytes(bytes(actualURI));
        
        // Verify 
        assertFalse(
            keccak256(bytes(actualURI)) == keccak256(bytes(expectedURI)),
            "URI malformed - uint256 encoded as 32-byte binary, not decimal string"
        );
    }
}