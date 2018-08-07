pragma solidity ^0.4.21;

import "./libs/SafeMath.sol";

contract TomoValidator {
    using SafeMath for uint256;

    event Vote(address _voter, address _candidate, uint256 _cap);
    event Unvote(address _voter, address _candidate, uint256 _cap);
    event Propose(address _owner, address _candidate, uint256 _cap);
    event Resign(address _owner, address _candidate);
    event SetNodeId(address _owner, address _candidate, string _nodeId);
    event Withdraw(address _owner, uint256 _blockNumber, uint256 _cap);

    struct ValidatorState {
        address owner;
        string nodeId;
        bool isCandidate;
        uint256 cap;
        mapping(address => uint256) voters;
    }

    struct WithdrawState {
      mapping(uint256 => uint256) caps;
      uint256[] blockNumbers;
    }

    mapping(address => WithdrawState) withdrawsState;

    mapping(address => ValidatorState) validatorsState;
    mapping(address => address[]) voters;
    address[] public candidates;

    uint256 public candidateCount = 3;
    uint256 public minCandidateCap;
    uint256 public maxValidatorNumber;
    uint256 public candidateWithdrawDelay;
    uint256 public voterWithdrawDelay;

    modifier onlyValidCandidateCap {
        // anyone can deposit X TOMO to become a candidate
        require(msg.value >= minCandidateCap);
        _;
    }

    modifier onlyOwner(address _candidate) {
        require(validatorsState[_candidate].owner == msg.sender);
        _;
    }

    modifier onlyCandidate(address _candidate) {
        require(validatorsState[_candidate].isCandidate);
        _;
    }

    modifier onlyValidCandidate (address _candidate) {
        require(validatorsState[_candidate].isCandidate);
        _;
    }

    modifier onlyNotCandidate (address _candidate) {
        require(!validatorsState[_candidate].isCandidate);
        _;
    }

    modifier onlyValidVote (address _candidate, uint256 _cap) {
        require(validatorsState[_candidate].voters[msg.sender] >= _cap);
        _;
    }

    modifier onlyValidWithdraw (uint256 _blockNumber, uint _index) {
        require(_blockNumber > 0);
        require(block.number >= _blockNumber);
        require(withdrawsState[msg.sender].caps[_blockNumber] > 0);
        require(withdrawsState[msg.sender].blockNumbers[_index] == _blockNumber);
        _;
    }

    function TomoValidator (
        address[] _candidates,
        uint256[] _caps,
        address _firstOwner,
        uint256 _minCandidateCap,
        uint256 _maxValidatorNumber,
        uint256 _candidateWithdrawDelay,
        uint256 _voterWithdrawDelay
    ) public {
        minCandidateCap = _minCandidateCap;
        maxValidatorNumber = _maxValidatorNumber;
        candidateWithdrawDelay = _candidateWithdrawDelay;
        voterWithdrawDelay = _voterWithdrawDelay;

        for (uint256 i = 0; i < _candidates.length; i++) {
            candidates.push(_candidates[i]);
            validatorsState[_candidates[i]] = ValidatorState({
                owner: _firstOwner,
                nodeId: '',
                isCandidate: true,
                cap: _caps[i]
            });
            voters[_candidates[i]].push(_firstOwner);
            validatorsState[candidates[i]].voters[_firstOwner] = minCandidateCap;
        }
    }

    function propose(address _candidate, string _nodeId) external payable onlyValidCandidateCap onlyNotCandidate(_candidate) {
        candidates.push(_candidate);
        validatorsState[_candidate] = ValidatorState({
            owner: msg.sender,
            nodeId: _nodeId,
            isCandidate: true,
            cap: msg.value
        });
        validatorsState[_candidate].voters[msg.sender] = msg.value;
        candidateCount = candidateCount + 1;
        voters[_candidate].push(_candidate);
        emit Propose(msg.sender, _candidate, msg.value);
    }

    function vote(address _candidate) external payable onlyValidCandidate(_candidate) {
        validatorsState[_candidate].cap = validatorsState[_candidate].cap.add(msg.value);
        if (validatorsState[_candidate].voters[msg.sender] == 0) {
            voters[_candidate].push(msg.sender);
        }
        validatorsState[_candidate].voters[msg.sender] = validatorsState[_candidate].voters[msg.sender].add(msg.value);
        emit Vote(msg.sender, _candidate, msg.value);
    }

    function getCandidates() public view returns(address[]) {
        return candidates;
    }

    function getCandidateCap(address _candidate) public view returns(uint256) {
        return validatorsState[_candidate].cap;
    }

    function getCandidateNodeId(address _candidate) public view returns(string) {
        return validatorsState[_candidate].nodeId;
    }

    function getCandidateOwner(address _candidate) public view returns(address) {
        return validatorsState[_candidate].owner;
    }

    function getVoterCap(address _candidate, address _voter) public view returns(uint256) {
        return validatorsState[_candidate].voters[_voter];
    }

    function getVoters(address _candidate) public view returns(address[]) {
        return voters[_candidate];
    }

    function isCandidate(address _candidate) public view returns(bool) {
        return validatorsState[_candidate].isCandidate;
    }

    function getWithdrawBlockNumbers() public view returns(uint256[]) {
        return withdrawsState[msg.sender].blockNumbers;
    }

    function unvote(address _candidate, uint256 _cap) public onlyValidVote(_candidate, _cap) {
        validatorsState[_candidate].cap = validatorsState[_candidate].cap.sub(_cap);
        validatorsState[_candidate].voters[msg.sender] = validatorsState[_candidate].voters[msg.sender].sub(_cap);

        // refund after delay X blocks
        uint256 withdrawBlockNumber = voterWithdrawDelay.add(block.number);
        withdrawsState[msg.sender].caps[withdrawBlockNumber] = withdrawsState[msg.sender].caps[withdrawBlockNumber].add(_cap);
        withdrawsState[msg.sender].blockNumbers.push(withdrawBlockNumber);

        emit Unvote(msg.sender, _candidate, _cap);
    }

    function setNodeId(address _candidate, string _nodeId) public onlyOwner(_candidate) {
        validatorsState[_candidate].nodeId = _nodeId;
        emit SetNodeId(msg.sender, _candidate, _nodeId);
    }

    function resign(address _candidate) public onlyOwner(_candidate) onlyCandidate(_candidate) {
        validatorsState[_candidate].isCandidate = false;
        candidateCount = candidateCount - 1;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == _candidate) {
                delete candidates[i];
                break;
            }
        }
        uint256 cap = validatorsState[_candidate].voters[msg.sender];
        validatorsState[_candidate].cap = validatorsState[_candidate].cap.sub(cap);
        validatorsState[_candidate].voters[msg.sender] = 0;
        // refunding after retiring X blocks
        uint256 withdrawBlockNumber = candidateWithdrawDelay.add(block.number);
        withdrawsState[msg.sender].caps[withdrawBlockNumber] = withdrawsState[msg.sender].caps[withdrawBlockNumber].add(cap);
        withdrawsState[msg.sender].blockNumbers.push(withdrawBlockNumber);
        emit Resign(msg.sender, _candidate);
    }

    function withdraw(uint256 _blockNumber, uint _index) public onlyValidWithdraw(_blockNumber, _index) {
        uint256 cap = withdrawsState[msg.sender].caps[_blockNumber];
        delete withdrawsState[msg.sender].caps[_blockNumber];
        delete withdrawsState[msg.sender].blockNumbers[_index];
        msg.sender.transfer(cap);
        emit Withdraw(msg.sender, _blockNumber, cap);
    }
}
