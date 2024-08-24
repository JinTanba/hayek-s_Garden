const ethers = await import("npm:ethers@6.10.0");


const API_KEYS = {
  1: secrets.ETHERSCAN_API_KEY ? secrets.ETHERSCAN_API_KEY : "",    // Ethereum Mainnet
  8453: secrets.BASESCAN_API_KEY ? secrets.BASESCAN_API_KEY : "",   // Base
  10: secrets.OPTIMISM_API_KEY ? secrets.OPTIMISM_API_KEY : ""      // Optimism
};

const API_URLS = {
  1: `${secrets.cabinet[0]}`, //cabinet-node
  8453: `${secrets.cabinet[1]}`, //cabinet-node
  42161:`${secrets.cabinet[2]}`// arbitrum
};

const NETWORK_NAMES = {
  1: 'Ethereum Mainnet',
  8453: 'Base',
  10: 'Arbitrum'
};

const CONTRACT_ADDRESS = args[3];
const startBlock = args[4];
const FUNCTIONS = [
    ...args.slice(5, args.length)
];

const FUNCTION_SIGNATURES = FUNCTIONS.map(func => ethers.id(func).slice(0, 10));
console.log('Function Signatures:', FUNCTION_SIGNATURES);

async function getContractTransactions(chainId, endBlock = 'latest') {
  if (![1, 8453, 10].includes(chainId)) {
    throw new Error('Unsupported chainId. Use 1 for Ethereum Mainnet, 8453 for Base, or 10 for Optimism.');
  }

  const API_KEY = API_KEYS[chainId];
  const API_URL = `https://gateway-api.cabinet-node.com/s${API_URLS[chainId]}`;

  try {
    const response = await Functions.makeHttpRequest({
      url: API_URL,
      method: 'GET',
      params: {
        module: 'account',
        action: 'txlist',
        address: CONTRACT_ADDRESS,
        startblock: startBlock,
        endblock: endBlock,
        sort: 'asc',
        apikey: API_KEY
      },
      responseType: 'json'
    });

    if (response.status === 200 && response.data.status === '1') {
      // 特定の関数シグネチャでフィルタリングしたトランザクションハッシュを返す
      return response.data.result
        .filter(tx => FUNCTION_SIGNATURES.some(sig => tx.input.startsWith(sig)))
        .map(tx => tx.hash);
    } else {
      throw new Error(`API Error: ${response.data.message}`);
    }
  } catch (error) {
    console.error(`Error fetching transactions for ${NETWORK_NAMES[chainId]}:`, error);
    return [];
  }
}

function hashTxList(txList) {
  // トランザクションハッシュリストを連結し、keccak256でハッシュ化
  const concatenatedHashes = txList.join('');
  return ethers.keccak256(ethers.toUtf8Bytes(concatenatedHashes));
}

async function main(chainIds) {
  try {
    const allTransactions = await Promise.all(
      chainIds.map(async (chainId) => {
        const txHashes = await getContractTransactions(chainId);
        const txListHash = hashTxList(txHashes);
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


return main([1, 8453, 10]);