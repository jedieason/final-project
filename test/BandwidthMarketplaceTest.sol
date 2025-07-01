// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "forge-std/Test.sol";
import "../contracts/BandwidthMarketplace.sol";

/// @title Tests for BandwidthMarketplace contract
contract BandwidthMarketplaceTest is Test {
    BandwidthMarketplace dvpn;
    SimpleToken token;
    address user;
    uint256 userPk;
    address provider;
    uint256 providerPk;
    address otherUser;
    uint256 otherUserPk;

    function setUp() public {
        token = new SimpleToken();
        dvpn = new BandwidthMarketplace(IERC20(address(token)));
        userPk = 0xA11CE;
        providerPk = 0xB0B;
        otherUserPk = 0xC0DE;
        user = vm.addr(userPk);
        provider = vm.addr(providerPk);
        otherUser = vm.addr(otherUserPk);
        token.mint(user, 10000 ether);
        token.mint(provider, 10000 ether);
        token.mint(otherUser, 10000 ether);
        vm.prank(user);
        token.approve(address(dvpn), type(uint256).max);
        vm.prank(provider);
        token.approve(address(dvpn), type(uint256).max);
        vm.prank(otherUser);
        token.approve(address(dvpn), type(uint256).max);
    }

    function testProviderRegistrationAndUpdate() public {
        vm.startPrank(provider);
        uint256 minStake = dvpn.MIN_STAKE();
        vm.expectRevert("Stake below minimum");
        dvpn.registerProvider(minStake - 1, 10);
        dvpn.registerProvider(minStake, 10);
        (address provAddr, uint256 stake, uint256 price, bool registered) = dvpn.providers(provider);
        assertEq(provAddr, provider);
        assertEq(stake, minStake);
        assertEq(price, 10);
        assertTrue(registered);
        vm.expectRevert("Already registered");
        dvpn.registerProvider(minStake, 10);
        dvpn.updatePricePerMB(20);
        (, , uint256 newPrice, ) = dvpn.providers(provider);
        assertEq(newPrice, 20);
        vm.expectRevert("Price must be > 0");
        dvpn.updatePricePerMB(0);
        vm.stopPrank();
    }

    function testStartSessionAndEndSessionDirect() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 5 ether);
        uint256 providerBalanceAfterStake = token.balanceOf(provider);
        vm.startPrank(user);
        vm.expectRevert("Deposit must be > 0");
        dvpn.startSession(provider, 0);
        vm.expectRevert("Provider not registered");
        dvpn.startSession(otherUser, 100 ether);
        uint256 sessionId = dvpn.startSession(provider, 100 ether);
        (address u, address p, uint256 price,, uint256 redeemed,, bool active) = dvpn.sessions(sessionId);
        assertEq(u, user);
        assertEq(p, provider);
        assertEq(price, 5 ether);
        assertEq(redeemed, 0);
        assertTrue(active);
        assertEq(token.balanceOf(address(dvpn)), 100 ether);
        assertEq(token.balanceOf(user), 10000 ether - 100 ether);
        uint256 usedMB = 10;
        dvpn.endSession(sessionId, usedMB);
        (, , , , , , bool activeAfter) = dvpn.sessions(sessionId);
        assertFalse(activeAfter);
        assertEq(token.balanceOf(provider), providerBalanceAfterStake + 50 ether);
        assertEq(token.balanceOf(user), 10000 ether - 100 ether + 50 ether);
        assertEq(token.balanceOf(address(dvpn)), 0);
        vm.stopPrank();
    }

    function testEndSessionCapsCost() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 10 ether);
        uint256 providerBalanceAfterStake = token.balanceOf(provider);
        vm.prank(user);
        uint256 sessionId = dvpn.startSession(provider, 100 ether);
        vm.prank(user);
        dvpn.endSession(sessionId, 20);
        assertEq(token.balanceOf(provider), providerBalanceAfterStake + 100 ether);
        assertEq(token.balanceOf(user), 10000 ether - 100 ether);
    }

    function testVoucherRedemptionFlow() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 1 ether);
        uint256 providerBalanceAfterStake = token.balanceOf(provider);
        vm.prank(user);
        uint256 sessionId = dvpn.startSession(provider, 10 ether);
        bytes32 message = keccak256(abi.encodePacked(sessionId, provider, uint256(4 ether), address(dvpn)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, ethHash);
        vm.prank(provider);
        dvpn.redeemVoucher(sessionId, 4 ether, v, r, s);
        assertEq(token.balanceOf(provider), providerBalanceAfterStake + 4 ether);
        assertEq(token.balanceOf(address(dvpn)), 6 ether);
        (, , , , uint256 redeemed1, , bool active1) = dvpn.sessions(sessionId);
        assertTrue(active1);
        assertEq(redeemed1, 4 ether);
        bytes32 message2 = keccak256(abi.encodePacked(sessionId, provider, uint256(8 ether), address(dvpn)));
        bytes32 ethHash2 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message2));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(userPk, ethHash2);
        vm.prank(provider);
        dvpn.redeemVoucher(sessionId, 8 ether, v2, r2, s2);
        assertEq(token.balanceOf(provider), providerBalanceAfterStake + 8 ether);
        assertEq(token.balanceOf(address(dvpn)), 2 ether);
        (, , , , uint256 redeemed2, , ) = dvpn.sessions(sessionId);
        assertEq(redeemed2, 8 ether);
        vm.prank(user);
        dvpn.withdrawLeftover(sessionId);
        assertEq(token.balanceOf(user), 10000 ether - 10 ether + 2 ether);
        assertEq(token.balanceOf(provider), providerBalanceAfterStake + 8 ether);
        assertEq(token.balanceOf(address(dvpn)), 0);
        (, , , , , , bool activeAfter) = dvpn.sessions(sessionId);
        assertFalse(activeAfter);
        bytes32 message3 = keccak256(abi.encodePacked(sessionId, provider, uint256(10 ether), address(dvpn)));
        bytes32 ethHash3 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message3));
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(userPk, ethHash3);
        vm.prank(provider);
        vm.expectRevert("Session not active");
        dvpn.redeemVoucher(sessionId, 10 ether, v3, r3, s3);
    }

    function testRedeemVoucherInvalidCases() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 1 ether);
        vm.prank(user);
        uint256 sessionId = dvpn.startSession(provider, 5 ether);
        bytes32 msgHash = keccak256(abi.encodePacked(sessionId, provider, uint256(2 ether), address(dvpn)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherUserPk, ethHash);
        vm.prank(provider);
        vm.expectRevert("Invalid signature");
        dvpn.redeemVoucher(sessionId, 2 ether, v, r, s);
        bytes32 msgHash2 = keccak256(abi.encodePacked(sessionId, provider, uint256(10 ether), address(dvpn)));
        bytes32 ethHash2 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash2));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(userPk, ethHash2);
        vm.prank(provider);
        vm.expectRevert("Amount exceeds deposit");
        dvpn.redeemVoucher(sessionId, 10 ether, v2, r2, s2);
        bytes32 msgHash3 = keccak256(abi.encodePacked(sessionId, provider, uint256(3 ether), address(dvpn)));
        bytes32 ethHash3 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash3));
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(userPk, ethHash3);
        vm.prank(provider);
        dvpn.redeemVoucher(sessionId, 3 ether, v3, r3, s3);
        vm.prank(provider);
        vm.expectRevert("Invalid amount (<= already redeemed)");
        dvpn.redeemVoucher(sessionId, 3 ether, v3, r3, s3);
        bytes32 msgHash4 = keccak256(abi.encodePacked(sessionId, provider, uint256(2 ether), address(dvpn)));
        bytes32 ethHash4 = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash4));
        (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(userPk, ethHash4);
        vm.prank(provider);
        vm.expectRevert("Invalid amount (<= already redeemed)");
        dvpn.redeemVoucher(sessionId, 2 ether, v4, r4, s4);
    }

    function testForceEndSession() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 1 ether);
        vm.prank(user);
        uint256 sessionId = dvpn.startSession(provider, 5 ether);
        vm.prank(provider);
        vm.expectRevert("Session timeout not reached");
        dvpn.forceEndSession(sessionId);
        vm.warp(block.timestamp + dvpn.SESSION_TIMEOUT());
        uint256 providerBalanceBefore = token.balanceOf(provider);
        vm.prank(provider);
        dvpn.forceEndSession(sessionId);
        assertEq(token.balanceOf(provider), providerBalanceBefore + 5 ether);
        (, , , , , , bool activeAfter) = dvpn.sessions(sessionId);
        assertFalse(activeAfter);
        vm.prank(user);
        vm.expectRevert("Session not active or ended");
        dvpn.withdrawLeftover(sessionId);
    }

    function testProviderDeregister() public {
        vm.prank(provider);
        dvpn.registerProvider(dvpn.MIN_STAKE(), 1 ether);
        vm.prank(user);
        uint256 sessionId = dvpn.startSession(provider, 1 ether);
        vm.prank(provider);
        vm.expectRevert("Active sessions ongoing");
        dvpn.deregisterProvider();
        vm.prank(user);
        dvpn.endSession(sessionId, 1);
        uint256 providerBalBefore = token.balanceOf(provider);
        vm.prank(provider);
        dvpn.deregisterProvider();
        uint256 minStake = dvpn.MIN_STAKE();
        assertEq(token.balanceOf(provider), providerBalBefore + minStake);
        (, uint256 stake,, bool registered) = dvpn.providers(provider);
        assertEq(stake, 0);
        assertFalse(registered);
    }
}

// Simple ERC20 token used for tests
contract SimpleToken {
    string public name = "BandwidthToken";
    string public symbol = "BWT";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Not enough balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Not enough balance");
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
