// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Hayek is EIP712 {
    using ECDSA for bytes32;

    address public crossChainOracle;
    event ProtocolRegistered(uint256 indexed protocolId, address indexed protocol, address owner, address rewardToken, uint256 rewardPool, bool isPermitedBase);
    event TxHashSubmitted(uint256 indexed protocolId, bytes32 indexed txHash, address indexed uiOwner);
    event PermitedAddressesAdded(uint256 indexed protocolId, address[] addresses);
    event PermitedAddressesRemoved(uint256 indexed protocolId, address[] addresses);
    event PoolFunded(uint256 indexed protocolId, uint256 amount);
    event PoolWithdrawn(uint256 indexed protocolId, uint256 amount);
    event RewardsDistributed(uint256 indexed protocolId, uint256 totalDistributed, uint256 remainingReward);

    struct Protocol {
        address protocol;
        address owner;
        address rewardToken; // address(0) for ETH
        uint256 rewardPool;
        bool isPermitedBase;
        bytes32 txHashListForDistribute;
    }

    uint256 public protocolId;
    mapping(uint256 protocolId => mapping(bytes32 txHash => address uiOwnerAddress)) public txHashToOwner;
    mapping(uint256 protocolId => Protocol) public protocols;
    mapping(uint256 protocolId => mapping(address => bool)) public isPermited;

    bytes32 private constant SUBMIT_TXHASH_TYPEHASH = 
        keccak256("SubmitTxhash(uint256 protocolId,bytes32 txHash,address txSender,address uiOwner)");

    constructor() EIP712("Hayek", "1") {}

    function submitTxhash(
        uint256 _protocolId,
        bytes32 _txHash,
        address txSender,
        bytes memory txSenderSig
    ) external {
        require(protocols[_protocolId].isPermitedBase == false || isPermited[_protocolId][msg.sender] == true, "UIS: not permited");
        
        bytes32 structHash = keccak256(abi.encode(
            SUBMIT_TXHASH_TYPEHASH,
            _protocolId,
            _txHash,
            txSender,
            msg.sender
        ));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(txSenderSig);

        require(signer == txSender, "UIS: Invalid signature");

        txHashToOwner[_protocolId][_txHash] = msg.sender;
        emit TxHashSubmitted(_protocolId, _txHash, msg.sender);
    }

    function getTxhashOwner(uint256 _protocolId, bytes32 _txHash) external view returns(address) {
        return txHashToOwner[_protocolId][_txHash];
    }

    // Protocol deployer
    function regist(
        address _protocol,
        address _rewardToken,
        uint256 _rewardPool,
        bool _isPermitedBase
    ) public payable {
        protocolId++;
        protocols[protocolId].protocol = _protocol;
        protocols[protocolId].owner = msg.sender;
        protocols[protocolId].rewardToken = _rewardToken;
        protocols[protocolId].isPermitedBase = _isPermitedBase;

        if (_rewardToken == address(0)) {
            require(msg.value == _rewardPool, "UIS: ETH amount must match _rewardPool");
            protocols[protocolId].rewardPool = msg.value;
        } else {
            protocols[protocolId].rewardPool = _rewardPool;
            require(IERC20(_rewardToken).transferFrom(msg.sender, address(this), _rewardPool), "USI: Fail to transfer");
        }

        emit ProtocolRegistered(protocolId, _protocol, msg.sender, _rewardToken, _rewardPool, _isPermitedBase);
    }

    function addPermited(uint256 _protocolId, address[] calldata _addressList) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");

        if(protocols[_protocolId].isPermitedBase == false) {
            protocols[_protocolId].isPermitedBase = true;
        }

        for(uint256 i = 0; i < _addressList.length; i++) {
            isPermited[_protocolId][_addressList[i]] = true;
        }

        emit PermitedAddressesAdded(_protocolId, _addressList);
    }

    function removePermited(uint256 _protocolId, address[] calldata _addressList) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        for(uint256 i = 0; i < _addressList.length; i++) {
            isPermited[_protocolId][_addressList[i]] = false;
        }

        emit PermitedAddressesRemoved(_protocolId, _addressList);
    }

    function fundPool(uint256 _protocolId, uint256 _amount) public payable {
        require(_amount > 0, "UIS: amount must be greater than 0");
        if (protocols[_protocolId].rewardToken == address(0)) {
            require(msg.value == _amount, "UIS: ETH amount must match _amount");
            protocols[_protocolId].rewardPool += msg.value;
        } else {
            IERC20(protocols[_protocolId].rewardToken).transferFrom(msg.sender, address(this), _amount);
            protocols[_protocolId].rewardPool += _amount;
        }

        emit PoolFunded(_protocolId, _amount);
    }

    function withdrawPool(uint256 _protocolId, uint256 _amount) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        require(_amount <= protocols[_protocolId].rewardPool, "UIS: amount must be less than rewardPool");
        
        if (protocols[_protocolId].rewardToken == address(0)) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20(protocols[_protocolId].rewardToken).transfer(msg.sender, _amount);
        }
        protocols[_protocolId].rewardPool -= _amount;

        emit PoolWithdrawn(_protocolId, _amount);
    }

    function commitTxHashListRootHash(uint256 _protocolId, bytes32 rootHash) public {
        require(msg.sender == crossChainOracle, "UIS: not owner");
        protocols[_protocolId].txHashListForDistribute = rootHash;
    }
 
    function distribute(uint256 _protocolId, bytes32[] memory txHashList) public {
        require(protocols[_protocolId].txHashListForDistribute == keccak256(abi.encodePacked(txHashList)), "UIS: txHashListForDistribute is empty");
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        
        protocols[_protocolId].txHashListForDistribute = 0;
        
        uint256 rewardPoolAmount = protocols[_protocolId].rewardPool;
        uint256 remainingReward = rewardPoolAmount;
        uint256 totalTx = txHashList.length;

        address[] memory uniqueAddresses = new address[](totalTx);
        uint256[] memory rewards = new uint256[](totalTx);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < totalTx; i++) {
            address uiOwnerAddress = txHashToOwner[_protocolId][txHashList[i]];
            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (uniqueAddresses[j] == uiOwnerAddress) {
                    rewards[j]++;
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueAddresses[uniqueCount] = uiOwnerAddress;
                rewards[uniqueCount] = 1;
                uniqueCount++;
            }
        }

        for (uint256 i = 0; i < uniqueCount; i++) {
            if (uniqueAddresses[i] != address(0)) {
                uint256 reward = (rewardPoolAmount * rewards[i]) / totalTx;
                if (reward > 0 && reward <= remainingReward) {
                    if (protocols[_protocolId].rewardToken == address(0)) {
                        payable(uniqueAddresses[i]).transfer(reward);
                    } else {
                        IERC20(protocols[_protocolId].rewardToken).transfer(uniqueAddresses[i], reward);
                    }
                    remainingReward -= reward;
                }
            }
        }

        if (remainingReward > 0) {
            if (protocols[_protocolId].rewardToken == address(0)) {
                payable(protocols[_protocolId].owner).transfer(remainingReward);
            } else {
                IERC20(protocols[_protocolId].rewardToken).transfer(protocols[_protocolId].owner, remainingReward);
            }
        }
        
        protocols[_protocolId].rewardPool = 0;

        emit RewardsDistributed(_protocolId, rewardPoolAmount, remainingReward);
    }

}

