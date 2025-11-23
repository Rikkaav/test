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

contract STBL_YLD_BurnDisabledNFTTest is Test {
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
    
    // Helper function to create default metadata with all 14 required fields
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

    function testBurnDisabledNFT_ShouldRevert() public {
        console.log("=== TEST: Proof of Bug - Disabled NFT Cannot Be Burned ===\n");
        
        // Step 1: Mint NFT to user
        console.log("Step 1: Minting NFT to user...");
        // Create metadata with all required fields (adjust based on actual struct)
        YLD_Metadata memory metadata = _createDefaultMetadata();
        
        vm.prank(minter);
        uint256 tokenId = yldContract.mint(user, metadata);
        
        console.log("  Token ID:", tokenId);
        console.log("  Owner:", yldContract.ownerOf(tokenId));
        console.log("  Is Disabled:", yldContract.getNFTData(tokenId).isDisabled);
        require(yldContract.ownerOf(tokenId) == user, "Mint failed");
        console.log("  NFT minted successfully\n");
        
        // Step 2: Admin disables the NFT
        console.log("Step 2: Admin disabling NFT...");
        vm.prank(admin);
        yldContract.disableNFT(tokenId);
        
        console.log("  Is Disabled:", yldContract.getNFTData(tokenId).isDisabled);
        require(yldContract.getNFTData(tokenId).isDisabled == true, "Disable failed");
        console.log("  NFT disabled successfully\n");
        
        // Step 3: Try to burn the disabled NFT (THIS SHOULD WORK BUT WILL FAIL!)
        console.log("Step 3: Attempting to burn disabled NFT...");
        console.log("  According to code comment: 'Burns are still allowed for disabled NFTs'");
        console.log("  Expected: Burn should succeed");
        console.log("  Actual: Burn will revert with STBL_YLD_TransferDisabled\n");
        
        // This will revert
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(STBL_YLD_TransferDisabled.selector, tokenId)
        );
        yldContract.burn(user, tokenId);
        
        console.log("  Burn reverted with STBL_YLD_TransferDisabled!");
        console.log("  This contradicts the developer's comment in _update()");
        console.log("  NFT is now permanently stuck and cannot be burned\n");
        
        // Verify NFT is still owned by user and disabled
        console.log("Step 4: Verifying NFT is stuck...");
        console.log("  Owner:", yldContract.ownerOf(tokenId));
        console.log("  Is Disabled:", yldContract.getNFTData(tokenId).isDisabled);
        console.log("  NFT is permanently stuck!\n");
    }
    
    function testBurnEnabledNFT_ShouldSucceed() public {
        console.log("\n=== CONTROL TEST: Enabled NFT Can Be Burned ===\n");
        
        // Mint NFT
        YLD_Metadata memory metadata = _createDefaultMetadata();
        
        vm.prank(minter);
        uint256 tokenId = yldContract.mint(user, metadata);
        console.log("Token ID:", tokenId);
        console.log("Owner:", yldContract.ownerOf(tokenId));
        
        // Burn enabled NFT (this should work)
        console.log("\nBurning enabled NFT...");
        vm.prank(minter);
        yldContract.burn(user, tokenId);
        
        console.log("Burn successful for enabled NFT");
        console.log("This proves burn() works fine when NFT is not disabled\n");
        
        // Verify burn succeeded
        vm.expectRevert();
        yldContract.ownerOf(tokenId);
        console.log("NFT no longer exists (burned successfully)\n");
    }
    
    /**
     * @notice Test demonstrating the complete bug scenario
     * @dev Shows the practical impact: admin cannot cleanup disabled NFTs
     */
    function testCompleteScenario_DisabledNFTPermanentlyStuck() public {
        console.log("\n=== COMPLETE BUG SCENARIO ===\n");
        
        // 1. User gets NFT
        console.log("1. User receives NFT");
        YLD_Metadata memory metadata = _createDefaultMetadata();
        vm.prank(minter);
        uint256 tokenId = yldContract.mint(user, metadata);
        console.log("   User owns NFT #", tokenId, "\n");
        
        // 2. User violates terms
        console.log("2. User violates protocol terms");
        console.log("   Admin decides to disable user's NFT\n");
        
        // 3. Admin disables NFT
        console.log("3. Admin disables NFT");
        vm.prank(admin);
        yldContract.disableNFT(tokenId);
        console.log("   NFT is now disabled (cannot be transferred)\n");
        
        // 4. Admin tries to burn/cleanup
        console.log("4. Admin wants to cleanup/burn the disabled NFT");
        console.log("   Expected: NFT should be burned and removed");
        console.log("   Actual: Burn fails!\n");
        
        vm.prank(minter);
        vm.expectRevert();
        yldContract.burn(user, tokenId);
        
        console.log("   RESULT: NFT cannot be burned!");
        console.log("   User still owns a disabled (useless) NFT");
        console.log("   Protocol cannot cleanup or remove it");
        console.log("   NFT is PERMANENTLY STUCK\n");
        
        // 5. Show the stuck state
        console.log("5. Final state:");
        console.log("   Owner:", yldContract.ownerOf(tokenId));
        console.log("   Is Disabled:", yldContract.getNFTData(tokenId).isDisabled);
        console.log("   Can Transfer: NO (disabled)");
        console.log("   Can Burn: NO (reverts)");
        console.log("   Status: PERMANENTLY STUCK \n");
    }
}