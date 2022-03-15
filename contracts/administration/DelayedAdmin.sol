// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "../components/SafeOwnable.sol";

contract DelayedAdmin is SafeOwnable {
    using Address for address;

    uint256 public constant PROPOSAL_MAX_OPERATION_COUNT = 10;
    uint256 public constant PROPOSAL_MIN_DELAY = 86400;

    struct Proposal {
        uint256 id;
        address target;
        address proposer;
        string[] signatures;
        bytes[] calldatas;
        uint256 eta;
        bool isExecuted;
        bool isCanceled;
    }

    uint256 public delayPeriod = PROPOSAL_MIN_DELAY;
    uint256 public nextProposalId;
    mapping(uint256 => Proposal) public proposals;

    event CreateProposal(
        uint256 indexed proposalId,
        address indexed target,
        string[] signatures,
        bytes[] calldatas,
        string description,
        uint256 eta
    );
    event ExecuteProposal(
        uint256 indexed proposalId,
        address indexed target,
        string[] signatures,
        bytes[] calldatas,
        uint256 eta
    );
    event CancelProposal(
        uint256 indexed proposalId,
        address indexed target,
        string[] signatures,
        bytes[] calldatas,
        uint256 eta
    );
    event SetDelayPeriod(uint256 oldPeriod, uint256 newPeriod);

    constructor(uint256 defaultDelayPeriod) {
        _setDelayPeriod(defaultDelayPeriod);
    }

    function setDelayPeriod(uint256 newDelayPeriod) public {
        require(_msgSender() == address(this), "SenderMustBeSelf");
        _setDelayPeriod(newDelayPeriod);
    }

    function _setDelayPeriod(uint256 newDelayPeriod) internal {
        require(newDelayPeriod >= PROPOSAL_MIN_DELAY, "DelayTooShort");
        emit SetDelayPeriod(delayPeriod, newDelayPeriod);
        delayPeriod = newDelayPeriod;
    }

    function hasProposal(uint256 proposalId) public view returns (bool) {
        return proposals[proposalId].eta != 0;
    }

    function propose(
        address target,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public virtual onlyOwner returns (uint256) {
        require(signatures.length == calldatas.length, "ParamLengthMismatch");
        require(signatures.length != 0, "NoAction");
        require(signatures.length <= PROPOSAL_MAX_OPERATION_COUNT, "TooManyActions");

        address proposer = _msgSender();
        uint256 proposalId = nextProposalId++;
        uint256 eta = block.timestamp + delayPeriod;
        proposals[proposalId] = Proposal({
            id: proposalId,
            target: target,
            proposer: proposer,
            signatures: signatures,
            calldatas: calldatas,
            eta: eta,
            isExecuted: false,
            isCanceled: false
        });
        emit CreateProposal(proposalId, target, signatures, calldatas, description, eta);

        return proposalId;
    }

    function execute(uint256 proposalId) public payable onlyOwner {
        require(hasProposal(proposalId), "ProposalNotExists");

        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.eta, "ETA");
        require(!proposal.isExecuted, "AlreadyExecuted");
        require(!proposal.isCanceled, "AlreadyExecuted");
        proposal.isExecuted = true;
        for (uint256 i = 0; i < proposal.signatures.length; i++) {
            _executeTransaction(proposal.target, proposal.signatures[i], proposal.calldatas[i]);
        }
        emit ExecuteProposal(proposalId, proposal.target, proposal.signatures, proposal.calldatas, proposal.eta);
    }

    function _executeTransaction(
        address target,
        string memory signature,
        bytes memory data
    ) internal returns (bytes memory) {
        return target.functionCall(abi.encodePacked(bytes4(keccak256(bytes(signature))), data));
    }

    function cancel(uint256 proposalId) external {
        require(hasProposal(proposalId), "ProposalNotExists");

        Proposal storage proposal = proposals[proposalId];
        require(!proposal.isExecuted, "AlreadyExecuted");
        require(!proposal.isCanceled, "AlreadyExecuted");
        proposal.isCanceled = true;
        emit CancelProposal(proposalId, proposal.target, proposal.signatures, proposal.calldatas, proposal.eta);
    }
}
