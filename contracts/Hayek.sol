// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Hayek {
    struct Protocol {
        address protocol;
        address owner;
        address rewardToken;
        uint256 rewardPool;
        bool isPermitedBase;
        mapping(address => bool) isPermited;
    }

    struct Var {
        mapping(address => uint256) poolCounter;
    }
    uint256 public protocolId;
    mapping(uint256 protocolId => mapping(bytes32 txHash => address uiOwnerAddress)) public txHashToOwner;
    mapping(uint256 protocolId => Protocol) public protocols;

    function getProtocol(uint256 _protocolId) public view returns(Protocol memory) {
        return protocols[_protocolId];
    }

    // Protocol deployer
    function regist(
        address _protocol,
        address _rewardToken,
        uint256 _rewardPool,
        bool _isPermitedBase
    ) public {
        protocolId++;
        protocols[protocolId].protocol = _protocol;
        protocols[protocolId].owner = msg.sender;
        protocols[protocolId].rewardToken = _rewardToken;
        protocols[protocolId].rewardPool = _rewardPool;
        protocols[protocolId].isPermitedBase = _isPermitedBase;
    }

    function addPermited(uint256 _protocolId, address[] _addressList) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");

        if(protocols[_protocolId].isPermitedBase == false) {
            protocols[_protocolId].isPermitedBase = true;
        }

        for(uint256 i = 0; i < _addressList.length; i++) {
            protocols[_protocolId].isPermited[_addressList[i]] = true;
        }
    }

    function removePermited(uint256 _protocolId, address[] _addressList) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        for(uint256 i = 0; i < _addressList.length; i++) {
            protocols[_protocolId].isPermited[_addressList[i]] = false;
        }
    }

    function fundPool(uint256 _protocolId, uint256 _amount) public {
        reuqire(_amount > 0, "UIS: amount must be greater than 0");
        IERC20(protocols[_protocolId].rewardToken).transferFrom(msg.sender, address(this), _amount);
        protocols[_protocolId].rewardPool += _amount;
    }

    function withdrawPool(uint256 _protocolId, uint256 _amount) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        require(_amount <= protocols[_protocolId].rewardPool, "UIS: amount must be less than rewardPool");
        IERC20(protocols[_protocolId].rewardToken).transfer(msg.sender, _amount);
        protocols[_protocolId].rewardPool -= _amount;
    }
 

    function distribute(uint256 _protocolId, bytes32[] memory txHashList) public {
        require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");
        
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
                    IERC20(protocols[_protocolId].rewardToken).transfer(uniqueAddresses[i], reward);
                    remainingReward -= reward;
                }
            }
        }

        if (remainingReward > 0) {
            IERC20(protocols[_protocolId].rewardToken).transfer(protocols[_protocolId].owner, remainingReward);
        }
        
        protocols[_protocolId].rewardPool = 0;
    }

    /// Client
    function submitTxhash(uint256 _protocolId, bytes32 _txHash) external {
        require(protocols[_protocolId].isPermited[msg.sender] == true, "UIS: not permited");
        txHashToOwner[_protocolId][_txHash] = msg.sender;
    }

    function getTxhashOwner(uint256 _protocolId, bytes32 _txHash) external view returns(address) {
        return txHashToOwner[_protocolId][_txHash];
    }

    


}