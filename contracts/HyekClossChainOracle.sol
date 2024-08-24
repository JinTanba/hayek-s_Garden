// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

interface IHayek {
    struct Protocol {
        address protocol;
        address owner;
        address rewardToken; // address(0) for ETH
        uint256 rewardPool;
        bool isPermitedBase;
        bytes32 txHashListForDistribute;
    }
    function commit(uint256 protocolId,bytes32 _requestId) external;
    function protocols(uint256 protocolId) external view returns (Protocol memory);
}

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract HayekCrossChainOracle is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    address hub;
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;
    uint64 public subscriptionId;
    uint32 public gasLimit;
    bytes32 public donID;


    struct Stack {
        uint256 protocolId;
    }

    mapping(bytes32 => Stack) public stacks;

    error UnexpectedRequestID(bytes32 requestId);

    event Response(bytes32 indexed requestId, bytes response, bytes err);

    constructor(
        address router
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {}

    function sendRequest(
        string memory source,
        uint256 protocolId,
        bytes memory encryptedSecretsUrls,
        string[] memory args
    ) external onlyOwner returns (bytes32 requestId) {
        IHayek.Protocol memory protocol = IHayek(hub).protocols(protocolId);
        require(protocol.owner == msg.sender, "HayekCrossChainOracle: not protocol owner"); 
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
            protocolId: protocolId
        });
        
    }

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        Stack memory stack = stacks[requestId];
        IHayek(hub).commit(stack.protocolId,abi.decode(response, (bytes32)));
        s_lastResponse = response;
        s_lastError = err;
        emit Response(requestId, s_lastResponse, s_lastError);
    }


}
