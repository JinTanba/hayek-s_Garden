// // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//////////////////////////////////////////////////////////////////////////////////////
//You need to commit to the Hayek contract a hash of the encoding of the list of all tx txHash
//received by the protocol by using chainlinkFunctions. You'll need to write the JS to compute the 
//valid hashes, using this contract as a reference. I'll also share the link to the ChainlinkFunctions 
//documentation, you should read that too.
/////////////////////////////////////////////////////////////////////////////////////////////

// https://docs.chain.link/chainlink-functions <------ this is documentation for chainlinkFunctions;

////////////////////////////////////////////////////////////////////////////////////////////////////
// On a lighter note, chainlinkFunction is a completely customizable off-chain implementation 
// that can be oracle-executed. In other words, implementations that read APIs such as baseScan, OpScan, Ethscan, etc. 
// can easily read the cross-chain state by executing them via ChainlinkFunction. I encourage anyone who uses this to use this method to make this protocol more secure and trustworthy.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


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

    string public source = "const ethers = await import('npm:ethers@6.10.0');const API_KEYS={1:secrets.ETHERSCAN_API_KEY?secrets.ETHERSCAN_API_KEY:'',8453:secrets.BASESCAN_API_KEY?secrets.BASESCAN_API_KEY:'',10:secrets.OPTIMISM_API_KEY?secrets.OPTIMISM_API_KEY:''};const API_URLS={1:'https://api.etherscan.io',8453:'https://api.basescan.io',10:'https://api.optimism.io',42161:'https://api.arbitrum.io'};const NETWORK_NAMES={1:'Ethereum Mainnet',8453:'Base',10:'Arbitrum'};const CONTRACT_ADDRESS=args[0];const startBlock=args[1];const FUNCTIONS=[...args.slice(2,args.length)];const FUNCTION_SIGNATURES=FUNCTIONS.map(func=>ethers.id(func).slice(0,10));console.log('Function Signatures:',FUNCTION_SIGNATURES);async function getContractTransactions(chainId,endBlock='latest'){if(![1,8453,10].includes(chainId)){throw new Error('Unsupported chainId. Use 1 for Ethereum Mainnet, 8453 for Base, or 10 for Optimism.');}const API_KEY=API_KEYS[chainId];const API_URL=API_URLS[chainId];try{const response=await Functions.makeHttpRequest({url:API_URL,method:'GET',params:{module:'account',action:'txlist',address:CONTRACT_ADDRESS,startblock:startBlock,endblock:endBlock,sort:'asc',apikey:API_KEY},responseType:'json'});if(response.status===200&&response.data.status==='1'){return response.data.result.filter(tx=>FUNCTION_SIGNATURES.some(sig=>tx.input.startsWith(sig))).map(tx=>({txHash:tx.hash,from:tx.from}));}else{throw new Error(`API Error: ${response.data.message}`);}}catch(error){console.error(`Error fetching transactions for ${NETWORK_NAMES[chainId]}:`,error);return[];}}function hashTxList(txList){const concatenatedHashes=txList.join('');return ethers.keccak256(ethers.toUtf8Bytes(concatenatedHashes));}async function main(chainIds){try{const allTransactions=await Promise.all(chainIds.map(async(chainId)=>{const txHashes=await getContractTransactions(chainId);const txListHash=hashTxList(txHashes);return{chainId,network:NETWORK_NAMES[chainId],txListHash,txCount:txHashes.length};}));const finalHash=hashTxList(allTransactions.map(tx=>tx.txListHash));console.log('Network Transaction List Hashes:',allTransactions);console.log('Final Aggregated Hash:',finalHash);return ethers.getBytes(finalHash);}catch(error){console.error('Error in main function:',error);return Functions.encodeString(`Error: ${error.message}`);}}return main([1,8453,10]);";
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

    constructor() FunctionsClient(router) ConfirmedOwner(msg.sender) {
    }

    function init(address _hub) external {
        require(hub == address(0), "HayekCrossChainOracle: already initialized");
        hub = _hub;
    }

    function getSubscriptionBalance() public view returns(uint256) {
        return IRouterForGetSubscriptionBalance(router).getSubscription(subscriptionId).balance;
    }

    function sendRequest(
        uint256 protocolId,
        bytes memory encryptedSecretsUrls, // -----> this should be made by gist API.
        string[] memory args, // -----> look sources args[0] is CONTRACT_ADDRESS, args[1] is startBlock, args[2: args.length] is FUNCTION_SIGNATURES(you want to contain to interface);
        uint256 sendAmount
    ) external returns (bytes32 requestId) {
        IHayek.Protocol memory protocol = IHayek(hub).protocols(protocolId);
        require(protocol.owner == msg.sender, "HayekCrossChainOracle: not protocol owner");
        
        uint256 oldBalance = getSubscriptionBalance();
        FunctionsRequest.Request memory req;
        req.addSecretsReference(encryptedSecretsUrls);
        req.initializeRequestForInlineJavaScript(source);
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