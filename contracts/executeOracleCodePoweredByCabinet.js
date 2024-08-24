const ethers = await import("npm:ethers@6.10.0");

//Cabinet Node RPC URL
//get key!!!!! ---->  https://app.cabinet-node.com/endpoints
const RPC_URLS = {
    1: `${secrets.cabinet[0]}`, //cabinet-node
    8453: `${secrets.cabinet[1]}`, //cabinet-node
    42161:`${secrets.cabinet[2]}`// arbitrum
};

const NETWORK_NAMES = {
  1: 'Ethereum Mainnet',
  8453: 'Base',
  42161: 'Arbitrum'
};

const CONTRACT_ADDRESS = args[0];
const startBlock = args[1];
const FUNCTIONS = [
    ...args.slice(2, args.length)
];

const FUNCTION_SIGNATURES = FUNCTIONS.map(func => ethers.id(func).slice(0, 10));
console.log('Function Signatures:', FUNCTION_SIGNATURES);

async function getContractTransactions(chainId, endBlock = 'latest') {
  if (![1, 8453, 10, 42161].includes(chainId)) {
    throw new Error('Unsupported chainId. Use 1 for Ethereum Mainnet, 8453 for Base, 10 for Optimism, or 42161 for Arbitrum.');
  }

  const provider = new ethers.JsonRpcProvider(`https://gateway-api.cabinet-node.com/${RPC_URLS[chainId]}`);
  
  try {
    const filter = {
      address: CONTRACT_ADDRESS,
      fromBlock: startBlock,
      toBlock: endBlock
    };

    const logs = await provider.getLogs(filter);

    const matchingTxHashes = [];

    for (const log of logs) {
      const tx = await provider.getTransaction(log.transactionHash);
      if (FUNCTION_SIGNATURES.some(sig => tx.data.startsWith(sig))) {
        matchingTxHashes.push({txHash: tx.hash, from: tx.from});
      }
    }

    return matchingTxHashes;
  } catch (error) {
    console.error(`Error fetching transactions for ${NETWORK_NAMES[chainId]}:`, error);
    return [];
  }
}

function hashTxList(txList) {
  const concatenatedHashes = txList.join('');
  return ethers.keccak256(ethers.toUtf8Bytes(concatenatedHashes));
}

async function main(chainIds) {
  try {
    const allTransactions = await Promise.all(
      chainIds.map(async (chainId) => {
        const txHashes = await getContractTransactions(chainId);
        const txListHash = hashTxList(txHashes.map(tx => tx.txHash));
        return { chainId, network: NETWORK_NAMES[chainId], txListHash, txCount: txHashes.length };
      })
    );

    const finalHash = hashTxList(allTransactions.map(tx => tx.txListHash));

    console.log('Network Transaction List Hashes:', allTransactions);
    console.log('Final Aggregated Hash:', finalHash);

    return ethers.getBytes(finalHash);
  } catch (error) {
    console.error('Error in main function:', error);
    return Functions.encodeString(`Error: ${error.message}`);
  }
}

return main([1, 8453, 10, 42161]);