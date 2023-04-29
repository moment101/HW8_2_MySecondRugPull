// SPDX-License-Identifier: MIT
pragma solidity >=0.4.24;

import "forge-std/Test.sol";
import "../src/FiatTokenV2_1.sol";

interface IProxy {
    // onlyAdmin
    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external;

    function name() external returns (string memory);

    function admin() external view returns (address);

    function implementation() external view returns (address);
}

contract FiatTokenV3Test is Test {
    // Owner, Admin, User
    address owner = 0xFcb19e6a322b27c06842A71e8c725399f049AE3a;
    address admin = 0x807a96288A1A408dBC13DE2b1d087d10356395d2;
    address alice = makeAddr("Alice"); // 白名單 whitelister
    address bob = makeAddr("Bob"); // whitelisted
    address alex = makeAddr("Alex"); // non white list

    // Contract
    address USDC_addr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    string MAINNET_RPC_URL =
        "https://eth-mainnet.g.alchemy.com/v2/FV1NlKDA3WOn6s_Bg32c4q6Z9A02W1ng";

    IProxy proxy;
    FiatTokenV3 tokenV3;
    FiatTokenV3 proxyToken;

    function setUp() public {
        uint256 forkId = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(forkId);
        proxy = IProxy(USDC_addr);
        tokenV3 = new FiatTokenV3();
    }

    function upgradeAndInitialProxyToken() public {
        vm.startPrank(admin);
        proxy.upgradeTo(address(tokenV3));
        console.log(proxy.implementation());
        assertEq(proxy.implementation(), address(tokenV3));
        proxyToken = FiatTokenV3(address(proxy));
        vm.stopPrank();
    }

    // Case 1: Can read on-chain admin address
    function test_Fork() public {
        vm.startPrank(admin);
        console.log(proxy.admin());
        assertEq(proxy.admin(), admin);
    }

    // Case 2: Admin can only call upgradeTo & upgradeToAndCall （Transparent Proxy）
    function testFail_admin_capability() public {
        upgradeAndInitialProxyToken();

        vm.startPrank(admin);
        proxyToken.initializeV3(alice); // Fail
    }

    // Case 3: Upgrade and initialize whitelister
    function test_upgrade() public {
        upgradeAndInitialProxyToken();

        vm.startPrank(owner);
        proxyToken.initializeV3(alice);
        assertEq(proxyToken.whitelister(), alice);
    }

    // Case 4: Can't initializV3 twice
    function testFail_repeatInitializeV3() public {
        upgradeAndInitialProxyToken();

        vm.startPrank(owner);
        proxyToken.initializeV3(alice);
        proxyToken.initializeV3(bob); // Fail
    }

    // Case 5: WhiteListed can mint unlimit token
    function test_mintToken() public {
        upgradeAndInitialProxyToken();

        vm.prank(owner);
        proxyToken.initializeV3(alice);

        vm.prank(alice);
        proxyToken.whitelist(bob);

        uint256 mintTokenAmount = 10 ** 50; // type(uint256).max will cause totalSupply overflow
        vm.prank(bob);
        proxyToken.mint(bob, mintTokenAmount);

        console.log(proxyToken.balanceOf(bob));
        assertEq(proxyToken.balanceOf(bob), mintTokenAmount);
    }

    // Case 6: unwhitelisted can't mint
    function testFail_mintToken_unwhitelisted() public {
        upgradeAndInitialProxyToken();

        vm.prank(owner);
        proxyToken.initializeV3(alice);

        uint256 mintTokenAmount = 1;
        vm.prank(bob);
        proxyToken.mint(bob, mintTokenAmount); // fail
    }

    // Case 7: Only whitelisted can transfer
    function test_whitelist_transfer(
        uint256 mintAmount,
        uint transferAmount
    ) public {
        vm.assume(mintAmount >= 1 * 10 ** 6);
        vm.assume(mintAmount <= 10000000000 * 10 ** 6);
        vm.assume(transferAmount <= mintAmount);

        upgradeAndInitialProxyToken();

        vm.prank(owner);
        proxyToken.initializeV3(alice);

        vm.prank(alice);
        proxyToken.whitelist(bob);

        uint256 mintTokenAmount = mintAmount;
        vm.startPrank(bob);
        proxyToken.mint(bob, mintTokenAmount);
        console.log("Before transfer Bob balance:", proxyToken.balanceOf(bob));

        uint256 beforeTransferBobBalance = proxyToken.balanceOf(bob);
        uint256 beforeTransferAlexBalance = proxyToken.balanceOf(alex);

        proxyToken.transfer(alex, transferAmount);

        uint256 afterTransferBobBalance = proxyToken.balanceOf(bob);
        uint256 afterTransferAlexBalance = proxyToken.balanceOf(alex);

        assertEq(
            beforeTransferBobBalance - transferAmount,
            afterTransferBobBalance
        );
        assertEq(
            beforeTransferAlexBalance + transferAmount,
            afterTransferAlexBalance
        );
    }
}
