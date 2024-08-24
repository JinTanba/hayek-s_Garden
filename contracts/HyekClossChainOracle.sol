// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC677 {
    function transferAndCall(address to, uint256 amount, bytes memory data) external returns (bool);
}

interface IRouterForGetSubscriptionBalance {
    struct Subscription {
        uint96 balance;
        address owner;
        uint96 blockedBalance;
        address proposedOwner;
        address[] consumers;
        bytes32 flags;
    }
    function getSubscription(uint64 subscriptionId) external view returns (Subscription memory);
}

interface IHayek {
    struct Protocol {
        address protocol;
        address owner;
        address rewardToken;
        uint256 rewardPool;
        bool isPermitedBase;
        bytes32 txHashListForDistribute;
    }
    function commit(uint256 protocolId, bytes32 _requestId) external;
    function protocols(uint256 protocolId) external view returns (Protocol memory);
}

contract HayekCrossChainOracle is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    address public constant router = 0xf9B8fc078197181C841c296C876945aaa425B278;
    address public constant link = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;
    address public hub; // TODO: Replace with actual hub address
    uint64 public constant subscriptionId = 152;
    bytes32 public constant donID = 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000;
    uint32 public constant gasLimit = 300000;

    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    struct Stack {
        uint256 protocolId;
        address sender;
        uint256 oldBalance;
    }

    mapping(bytes32 => Stack) public stacks;

    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event LinkReport(uint256 oldBalance, uint256 newBalance);

    constructor(address _hub) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        hub = _hub;
    }

    function getSubscriptionBalance() public view returns(uint256) {
        return IRouterForGetSubscriptionBalance(router).getSubscription(subscriptionId).balance;
    }

    function sendRequest(
        string memory source,
        uint256 protocolId,
        bytes memory encryptedSecretsUrls,
        string[] memory args,
        uint256 sendAmount
    ) external returns (bytes32 requestId) {
        IHayek.Protocol memory protocol = IHayek(hub).protocols(protocolId);
        require(protocol.owner == msg.sender, "HayekCrossChainOracle: not protocol owner");
        
        uint256 oldBalance = getSubscriptionBalance();
        
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);
        req.addSecretsReference(encryptedSecretsUrls);
        req.setArgs(args);

        requestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        stacks[requestId] = Stack({
            protocolId: protocolId,
            sender: msg.sender,
            oldBalance: oldBalance
        });
        
        depositLink(msg.sender, sendAmount);
        return requestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        Stack memory stack = stacks[requestId];
        uint256 payedLink = Storage._linkDeposit()[stack.sender];
        uint256 newBalance = getSubscriptionBalance();
        emit LinkReport(stack.oldBalance, newBalance);
        uint256 usedLink = stack.oldBalance - newBalance;
        refund(payedLink - usedLink, stack.sender);
        IHayek(hub).commit(stack.protocolId, abi.decode(response, (bytes32)));
        s_lastResponse = response;
        s_lastError = err;
        emit Response(requestId, s_lastResponse, s_lastError);
    }

    // LINK token management functions
    function depositLink(address from, uint256 sendAmount) public {
        Storage._linkDeposit()[from] += sendAmount;
        IERC20(link).transferFrom(from, address(this), sendAmount);
    }

    function refund(uint256 amount, address sender) internal {
        IERC677(link).transferAndCall(router, amount, abi.encode(subscriptionId));
        uint256 depositBalance = Storage._linkDeposit()[sender];
        if(depositBalance > amount) {
            IERC20(link).transfer(sender, depositBalance - amount);
        }
        Storage._linkDeposit()[sender] -= amount;
    }
}

library Storage {
    uint8 constant LINK_DEPOSIT_SLOT = 1;

    function _linkDeposit() internal pure returns(mapping(address => uint256) storage _s) {
        assembly {
            mstore(0, LINK_DEPOSIT_SLOT)
            _s.slot := keccak256(0, 32)
        }
    }
}