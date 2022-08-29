// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.10;

import "../interfaces/IReferralManager.sol";
import "../components/SafeOwnableUpgradeable.sol";

contract TestReferralManager is SafeOwnableUpgradeable, IReferralManager {
    uint256 public constant RATE_DENOMINATOR = 100000; // 1e5 = 100%
    uint256 public immutable PRIMARY_NETWORK = 31337; //  by default, 42161 (arbitrum)

    mapping(bytes32 => address) public referralCodeOwners;
    bytes32 private __deprecated0;
    bytes32 private __deprecated1;
    TierSetting[] public tierSettings;

    address public maintainer;
    mapping(address => bool) public isHandler;
    mapping(bytes32 => address) public rebateRecipients;
    mapping(address => bytes32) public referralCodeOf;
    mapping(address => uint256) public lastUpdatedTime;

    modifier onlyPrimaryNetwork() {
        require(block.chainid == PRIMARY_NETWORK, "ReferralManager::isValidReferralCode::OnlyPrimaryNetwork");
        _;
    }

    modifier onlyMaintainer() {
        require(msg.sender == maintainer, "ReferralManager::onlyMaintainer::OnlyMaintainer");
        _;
    }

    /// @notice Initialize contract, set owner
    function initialize() external initializer {
        __SafeOwnable_init();
    }

    // ================================= management methods =================================
    /// @notice Set handler of referralManager
    function setHandler(address handler, bool enable) external onlyOwner {
        require(isHandler[handler] != enable, "ReferralManager::setHandler::AlreadySet");
        isHandler[handler] = enable;
        emit SetHandler(handler, enable);
    }

    function setMaintainer(address newMaintainer) external onlyOwner onlyPrimaryNetwork {
        require(newMaintainer != maintainer, "ReferralManager::setMaintainer::Duplicated");
        emit SetMaintainer(maintainer, newMaintainer);
        maintainer = newMaintainer;
    }

    function getTiers() external view returns (TierSetting[] memory) {
        return tierSettings;
    }

    function setTiers(TierSetting[] memory newTierSettings) external onlyPrimaryNetwork onlyOwner {
        uint256 rawLength = tierSettings.length;
        uint256 expLength = newTierSettings.length;
        uint256 length = rawLength > expLength ? rawLength : expLength;
        for (uint256 i = 0; i < length; i++) {
            if (i >= expLength) {
                tierSettings.pop();
            } else {
                TierSetting memory setting = newTierSettings[i];
                require(setting.tier == i, "ReferralManager::setTier::TierOutOfOrder");
                require(setting.discountRate <= RATE_DENOMINATOR, "ReferralManager::setTier::DiscountOutOfRange");
                require(setting.rebateRate <= RATE_DENOMINATOR, "ReferralManager::setTier::RebateRateOutOfRange");
                if (i >= rawLength) {
                    tierSettings.push(setting);
                } else {
                    tierSettings[i] = setting;
                }
            }
        }
        emit SetTiers(newTierSettings);
    }

    // methods only available on primary network
    function isValidReferralCode(bytes32 referralCode) public view onlyPrimaryNetwork returns (bool) {
        return referralCodeOwners[referralCode] != address(0);
    }

    function registerReferralCode(bytes32 referralCode, address rebateRecipient) external onlyPrimaryNetwork {
        require(referralCode != bytes32(0), "ReferralManager::registerReferralCode::ZeroCode");
        require(!isValidReferralCode(referralCode), "ReferralManager::registerReferralCode::InvalidCode");
        referralCodeOwners[referralCode] = msg.sender;
        emit RegisterReferralCode(msg.sender, referralCode);

        _setRebateRecipient(referralCode, rebateRecipient);
    }

    function setRebateRecipient(bytes32 referralCode, address rebateRecipient) external onlyPrimaryNetwork {
        require(msg.sender == referralCodeOwners[referralCode], "ReferralManager::setRebateRecipient::OnlyCodeOwner");
        _setRebateRecipient(referralCode, rebateRecipient);
    }

    function _setRebateRecipient(bytes32 referralCode, address rebateRecipient) internal {
        address codeOwner = referralCodeOwners[referralCode];
        address recipient = rebateRecipient == address(0) ? codeOwner : rebateRecipient;
        rebateRecipients[referralCode] = recipient;
        emit SetRebateRecipient(referralCode, codeOwner, recipient);
    }

    function transferReferralCode(bytes32 referralCode, address newOwner) external onlyPrimaryNetwork {
        require(msg.sender == referralCodeOwners[referralCode], "ReferralManager::setRebateRecipient::OnlyCodeOwner");
        referralCodeOwners[referralCode] = newOwner;
        emit TransferReferralCode(referralCode, msg.sender, newOwner);
    }

    // methods available on secondary network
    function getReferralCodeOf(address trader) external view returns (bytes32, uint256) {
        return (referralCodeOf[trader], lastUpdatedTime[trader]);
    }

    function setReferrerCode(bytes32 referralCode) external {
        referralCodeOf[msg.sender] = referralCode;
        lastUpdatedTime[msg.sender] = block.timestamp;
        emit SetReferralCode(msg.sender, referralCode);
    }

    function setReferrerCodeFor(address trader, bytes32 referralCode) external {
        require(isHandler[msg.sender], "ReferralManager::setReferrerCodeFor::onlyHandler");
        referralCodeOf[trader] = referralCode;
        lastUpdatedTime[trader] = block.timestamp;
        emit SetReferralCode(trader, referralCode);
    }
}
