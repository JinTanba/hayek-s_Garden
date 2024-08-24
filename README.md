# 🧐🎨Hayek protocol

Smart contracts can operate regardless of the interface used to interact with them. They can be called from rich UIs or scripts, right? This characteristic suggests the following possibility: 

A single protocol will have multiple interfaces, with optimized UIs developed by entities separate from the protocol developers for each anticipated user group. This ensures that the optimal UIX is always realized for all users. As a result, even inherently complex protocols can be expressed in UIX tailored to each user's needs, making them accessible to many people. 

However, this is not happening. The "challenge of mass adoption" has become the biggest hurdle facing Web3. This protocol, named after the economist who advocated for the superiority of decentralized decision-making over centralized decision-making, drives developers worldwide, including those from Web2, to improve Web3 UIX by defining the necessary economic incentives. This competition creates a selective pressure that constantly favors and realizes good UIX, naturally filtering out inferior interfaces. We are confident that HyekProtocol will be an effective move towards mass adoption of Web3!!! The contributions that HyekProtocol brings to the Web3 world are as follows: 
1. Encouraging developers and designers worldwide to compete in developing UIs and improving UX.
2. Decentralizing decision-making regarding UIX design and planning.
3. Overcoming single points of failure in UI (indestructible frontend). 4. An effective step towards mass adoption of Web3.

## Technical Section

### Overview

HyekProtocol is an innovative incentive system designed to promote the improvement of UIX (User Interface/User Experience) in Web3 protocols. This system accurately tracks UI developers' contributions and fairly distributes rewards, thereby encouraging continuous UIX enhancement and promoting mass adoption of Web3.

### Key Points of the Incentive Design

1. **Reward Pool Setup**: 
Protocol developers set up reward pools using ETH or ERC20 tokens, ensuring sustained incentives for UI developers.

2. **Transaction-based Contribution Tracking**:
The system records transaction hashes executed through each UI, accurately measuring the actual usage of each interface.

3. **Fair Reward Distribution**:
Rewards are calculated and distributed based on the number of recorded transaction hashes, ensuring compensation proportional to each UI's popularity and utility.

4. **Flexible Access Control**:
Protocol developers can manage a list of trusted UI developers, promoting high-quality UI development while mitigating potential misuse.

### Technical Implementation Details

#### 1. Protocol Registration and Reward Pool Setup

Protocol developers use the `regist` function to register their protocol and set up the reward pool:

```solidity
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
}
```

This function assigns a unique ID to each protocol and allows the use of either ETH or ERC20 tokens as rewards.

#### 2. Tracking UI Developer Contributions

UI developers submit transaction hashes executed through their UI using the `submitTxhash` function:

```solidity
function submitTxhash(uint256 _protocolId, bytes32 _txHash) external {
require(protocols[_protocolId].isPermitedBase == false || protocols[_protocolId].isPermited[msg.sender] == true, "UIS: not permited");
txHashToOwner[_protocolId][_txHash] = msg.sender;
}
```

This function checks the protocol's access control and associates the transaction hash with the UI developer's address.

#### 3. Reward Distribution Mechanism

Protocol owners call the `distribute` function to distribute rewards:

```solidity
function distribute(uint256 _protocolId, bytes32[] memory txHashList) public {
require(protocols[_protocolId].owner == msg.sender, "UIS: not owner");

uint256 rewardPoolAmount = protocols[_protocolId].rewardPool;
uint256 remainingReward = rewardPoolAmount;
uint256 totalTx = txHashList.length;

address[] memory uniqueAddresses = new address[](totalTx);
uint256[] memory rewards = new uint256[](totalTx);
uint256 uniqueCount = 0;

// Reward calculation and distribution logic
// ...
}
```

This function calculates and distributes rewards to UI developers based on the submitted transaction hashes.

#### 4. Dynamic Reward Pool Management

Protocol owners can dynamically manage the reward pool using the `fundPool` and `withdrawPool` functions:

```solidity
function fundPool(uint256 _protocolId, uint256 _amount) public payable {
// Logic to add funds to the reward pool
}

function withdrawPool(uint256 _protocolId, uint256 _amount) public {
// Logic to withdraw funds from the reward pool
}
```

These functions allow protocol owners to flexibly adjust the reward pool.

### Conclusion

The technical implementation of HyekProtocol provides a mechanism to accurately track UI developers' contributions and fairly distribute rewards. Simultaneously, it offers flexible management tools to protocol owners, enabling the construction of a long-term, sustainable ecosystem. This design effectively promotes UIX improvement and mass adoption of Web3, potentially allowing more users to access and utilize Web3 technologies.

By incentivizing continuous improvement and competition among UI developers, HyekProtocol aims to solve the "last mile" problem in Web3 adoption, making decentralized applications more accessible and user-friendly for a broader audience.


# ⚠️⚠️

In this protocol, txHash plays a crucial role. The contract, in an effort to avoid requiring additional descriptions from the client protocol, places a somewhat greater technical burden on UI developers. To ensure that UI developers receive rewards for their contributions, the following is recommended:

By using rawTransaction, understand the txHash before sending it to the network, and then send it to the HeyakContract. This allows you to be the first in the world to know the txHash, which is the treasure here!

```javascript
async function getTransactionHash(fromAddress, toAddress, value, data = '') {
  try {
    // Get the current nonce
    const nonce = await web3.eth.getTransactionCount(fromAddress);

    // Get the current gas price
    const gasPrice = await web3.eth.getGasPrice();

    // Estimate gas limit
    const gasLimit = await web3.eth.estimateGas({
      from: fromAddress,
      to: toAddress,
      value: web3.utils.toWei(value, 'ether'),
      data: data
    });

    // Create the transaction object
    const txObject = {
      nonce: web3.utils.toHex(nonce),
      to: toAddress,
      value: web3.utils.toHex(web3.utils.toWei(value, 'ether')),
      gasLimit: web3.utils.toHex(gasLimit),
      gasPrice: web3.utils.toHex(gasPrice),
      data: data
    };

    // Sign the transaction (you would normally do this with the actual private key)
    const signedTx = await web3.eth.accounts.signTransaction(txObject, 'YOUR_PRIVATE_KEY');

    // Get the raw transaction
    const rawTransaction = signedTx.rawTransaction;

    // Calculate and return the transaction hash
    const txHash = web3.utils.sha3(rawTransaction);
    return txHash;
  } catch (error) {
    console.error('Error in getTransactionHash:', error);
    throw error;
  }
}

```
