
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title BandwidthMarketplace - decentralized VPN bandwidth marketplace contract
 */
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract BandwidthMarketplace {
    IERC20 public token;
    uint256 public constant MIN_STAKE = 1000e18;
    uint256 public constant SESSION_TIMEOUT = 1 days;
    uint256 private nextSessionId = 1;

    struct Provider {
        address providerAddress;
        uint256 stake;
        uint256 pricePerMB;
        bool registered;
    }

    struct Session {
        address user;
        address provider;
        uint256 pricePerMB;
        uint256 deposit;
        uint256 redeemed;
        uint256 startTime;
        bool active;
    }

    mapping(address => Provider) public providers;
    mapping(uint256 => Session) public sessions;
    mapping(address => uint256) public activeSessionsCount;

    event ProviderRegistered(address indexed provider, uint256 stake, uint256 pricePerMB);
    event ProviderDeregistered(address indexed provider);
    event SessionStarted(uint256 indexed sessionId, address indexed user, address indexed provider, uint256 deposit);
    event VoucherRedeemed(uint256 indexed sessionId, uint256 amountPaid);
    event SessionEnded(uint256 indexed sessionId, uint256 amountPaid, uint256 refund);

    constructor(IERC20 _token) {
        token = _token;
    }

    function registerProvider(uint256 stakeAmount, uint256 pricePerMB) external {
        require(!providers[msg.sender].registered, "Already registered");
        require(stakeAmount >= MIN_STAKE, "Stake below minimum");
        require(pricePerMB > 0, "Price must be > 0");
        require(token.transferFrom(msg.sender, address(this), stakeAmount), "Stake transfer failed");
        providers[msg.sender] = Provider({
            providerAddress: msg.sender,
            stake: stakeAmount,
            pricePerMB: pricePerMB,
            registered: true
        });
        emit ProviderRegistered(msg.sender, stakeAmount, pricePerMB);
    }

    function updatePricePerMB(uint256 newPrice) external {
        Provider storage prov = providers[msg.sender];
        require(prov.registered, "Not a provider");
        require(newPrice > 0, "Price must be > 0");
        prov.pricePerMB = newPrice;
    }

    function deregisterProvider() external {
        Provider storage prov = providers[msg.sender];
        require(prov.registered, "Not a provider");
        require(activeSessionsCount[msg.sender] == 0, "Active sessions ongoing");
        uint256 refundStake = prov.stake;
        prov.stake = 0;
        prov.registered = false;
        require(token.transfer(msg.sender, refundStake), "Stake refund failed");
        emit ProviderDeregistered(msg.sender);
    }

    function startSession(address provider, uint256 depositAmount) external returns (uint256 sessionId) {
        Provider storage prov = providers[provider];
        require(prov.registered, "Provider not registered");
        require(depositAmount > 0, "Deposit must be > 0");
        require(token.transferFrom(msg.sender, address(this), depositAmount), "Deposit transfer failed");

        sessionId = nextSessionId++;
        sessions[sessionId] = Session({
            user: msg.sender,
            provider: provider,
            pricePerMB: prov.pricePerMB,
            deposit: depositAmount,
            redeemed: 0,
            startTime: block.timestamp,
            active: true
        });
        activeSessionsCount[provider] += 1;
        emit SessionStarted(sessionId, msg.sender, provider, depositAmount);
    }

    function endSession(uint256 sessionId, uint256 usedMB) external {
        Session storage ses = sessions[sessionId];
        require(ses.active, "Session not active");
        require(msg.sender == ses.user, "Only user can end");
        require(ses.redeemed == 0, "Voucher used");
        ses.active = false;
        activeSessionsCount[ses.provider] -= 1;
        uint256 cost = usedMB * ses.pricePerMB;
        if (cost > ses.deposit) {
            cost = ses.deposit;
        }
        uint256 payout = cost;
        uint256 refund = ses.deposit - cost;
        if (payout > 0) {
            require(token.transfer(ses.provider, payout), "Payout failed");
        }
        if (refund > 0) {
            require(token.transfer(ses.user, refund), "Refund failed");
        }
        emit SessionEnded(sessionId, payout, refund);
    }

    function redeemVoucher(uint256 sessionId, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        Session storage ses = sessions[sessionId];
        require(ses.active, "Session not active");
        require(msg.sender == ses.provider, "Only provider can redeem");
        bytes32 message = keccak256(abi.encodePacked(sessionId, ses.provider, amount, address(this)));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        address signer = ecrecover(ethHash, v, r, s);
        require(signer == ses.user, "Invalid signature");
        require(amount <= ses.deposit, "Amount exceeds deposit");
        require(amount > ses.redeemed, "Invalid amount (<= already redeemed)");
        uint256 newPayment = amount - ses.redeemed;
        ses.redeemed = amount;
        bool finalPayment = (amount == ses.deposit);
        if (finalPayment) {
            ses.active = false;
            activeSessionsCount[ses.provider] -= 1;
        }
        if (newPayment > 0) {
            require(token.transfer(ses.provider, newPayment), "Payment failed");
        }
        if (finalPayment) {
            emit SessionEnded(sessionId, amount, 0);
        } else {
            emit VoucherRedeemed(sessionId, amount);
        }
    }

    function withdrawLeftover(uint256 sessionId) external {
        Session storage ses = sessions[sessionId];
        require(ses.active, "Session not active or ended");
        require(msg.sender == ses.user, "Only user can withdraw");
        ses.active = false;
        activeSessionsCount[ses.provider] -= 1;
        uint256 alreadyPaid = ses.redeemed;
        uint256 refund = ses.deposit - alreadyPaid;
        if (refund > 0) {
            require(token.transfer(ses.user, refund), "Refund failed");
        }
        emit SessionEnded(sessionId, alreadyPaid, refund);
    }

    function forceEndSession(uint256 sessionId) external {
        Session storage ses = sessions[sessionId];
        require(ses.active, "Session not active");
        require(msg.sender == ses.provider, "Only provider can force end");
        require(block.timestamp >= ses.startTime + SESSION_TIMEOUT, "Session timeout not reached");
        ses.active = false;
        activeSessionsCount[ses.provider] -= 1;
        uint256 remaining = ses.deposit - ses.redeemed;
        if (remaining > 0) {
            require(token.transfer(ses.provider, remaining), "Payout failed");
        }
        emit SessionEnded(sessionId, ses.deposit, 0);
    }
}
