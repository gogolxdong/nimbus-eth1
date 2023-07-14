{.push raises: [].}

import
  std/[times, tables, typetraits, sequtils],
  json_rpc/[rpcserver,jsonmarshal], hexstrings, stint, stew/byteutils,
  json_serialization, web3/conversions, json_serialization/std/options,
  eth/common/[eth_types_json_serialization, eth_types],
  eth/[keys, rlp, p2p],
  ".."/[transaction, vm_state, constants],
  ../db/[state_db, incomplete_db, distinct_tries, storage_types],
  rpc_types, rpc_utils,
  ../transaction/call_evm,
  ../core/tx_pool,
  ../common/[common, context],
  ../utils/utils,
  ./filters, ../evm/async/data_sources/json_rpc_data_source,
  ../evm/[types, state], ../db/accounts_cache


#[
  Note:
    * Hexstring types (HexQuantitySt, HexDataStr, EthAddressStr, EthHashStr)
      are parsed to check format before the RPC blocks are executed and will
      raise an exception if invalid.
    * Many of the RPC calls do not validate hex string types when output, only
      type cast to avoid extra processing.
]#

proc setupEthRpc*(
    node: EthereumNode, ctx: EthContext, com: CommonRef,
    txPool: TxPoolRef, server: RpcServer) =

  let chainDB = com.db
  proc getStateDB(header: BlockHeader): state_db.ReadOnlyStateDB =
    let ac = newAccountStateDB(chainDB.db, header.stateRoot, com.pruneTrie)
    result = state_db.ReadOnlyStateDB(ac)

  proc stateDBFromTag(tag: string, readOnly = true): state_db.ReadOnlyStateDB {.gcsafe, raises: [CatchableError].} =
    result = getStateDB(chainDB.headerFromTag(tag))

  server.rpc("eth_protocolVersion") do() -> Option[string]:
    info "eth_protocolVersion"
    for n in node.capabilities:
      if n.name == "eth":
        return some($n.version)
    return none(string)

  server.rpc("eth_chainId") do() -> HexQuantityStr:
    return encodeQuantity(distinctBase(com.chainId))

  server.rpc("eth_syncing") do() -> JsonNode:
    info "eth_syncing"
    let numPeers = node.peerPool.connectedNodes.len
    if numPeers > 0:
      var sync = SyncState(
        startingBlock: encodeQuantity com.syncStart,
        currentBlock : encodeQuantity com.syncCurrent,
        highestBlock : encodeQuantity com.syncHighest
      )
      result = %sync
    else:
      result = newJBool(false)

  server.rpc("eth_coinbase") do() -> EthAddress:
    info "eth_coinbase"
    result = default(EthAddress)

  server.rpc("eth_mining") do() -> bool:
    info "eth_mining"
    result = false

  server.rpc("eth_hashrate") do() -> HexQuantityStr:
    info "eth_hashrate"
    result = encodeQuantity(0.uint)

  server.rpc("eth_gasPrice") do() -> HexQuantityStr:
    info "eth_gasPrice"
    result = encodeQuantity(calculateMedianGasPrice(chainDB).uint64)

  server.rpc("eth_accounts") do() -> seq[EthAddressStr]:
    info "eth_accounts"
    result = newSeqOfCap[EthAddressStr](ctx.am.numAccounts)
    for k in ctx.am.addresses:
      result.add ethAddressStr(k)

  server.rpc("eth_blockNumber") do() -> HexQuantityStr:
    result = encodeQuantity(chainDB.getCanonicalHead().blockNumber)

  server.rpc("setBalance") do(data: EthAddressStr, balance: HexQuantityStr) -> HexQuantityStr:
    let sender = data.toAddress
    let header = chainDB.getCanonicalHead()
    var client = waitFor makeAnRpcClient("http://149.28.74.252:8545")
    let (acc, accProof, storageProofs) = waitFor fetchAccountAndSlots(client, sender, @[], header.blockNumber)
    var accBalance = acc.balance

    populateDbWithBranch(chainDB.db, accProof)
    info "setBalance", sender=sender, accBalance=accBalance, blockNumber=header.blockNumber
    for index, storageProof in storageProofs:
      let slot: UInt256 = storageProof.key
      let fetchedVal: UInt256 = storageProof.value
      let storageMptNodes: seq[seq[byte]] = storageProof.proof.mapIt(distinctBase(it))
      let storageVerificationRes = verifyFetchedSlot(acc.storageRoot, slot, fetchedVal, storageMptNodes)
      let whatAreWeVerifying = ("storage proof", sender, acc, slot, fetchedVal)
      raiseExceptionIfError(whatAreWeVerifying, storageVerificationRes)

      populateDbWithBranch(chainDB.db, storageMptNodes)
      let slotAsKey = createTrieKeyFromSlot(slot)
      let slotHash = keccakHash(slotAsKey)
      let slotEncoded = rlp.encode(slot)
      chainDB.db.put(slotHashToSlotKey(slotHash.data).toOpenArray, slotEncoded)
    result = encodeQuantity accBalance

  server.rpc("eth_getBalance") do(data: EthAddressStr, quantityTag: string) -> HexQuantityStr:
    info "eth_getBalance", data=data.string, quantityTag=quantityTag
    let
      accDB   = stateDBFromTag(quantityTag)
      address = data.toAddress
      balance = accDB.getBalance(address)
    result = encodeQuantity(balance)

  server.rpc("eth_getStorageAt") do(data: EthAddressStr, slot: HexDataStr, quantityTag: string) -> HexDataStr:
    info "eth_getStorageAt", data=data.string, slot=slot.string, quantityTag=quantityTag
    let
      accDB   = stateDBFromTag(quantityTag)
      address = data.toAddress
      key     = fromHex(UInt256, slot.string)
      value   = accDB.getStorage(address, key)[0]
    result = hexDataStr(value)

  server.rpc("eth_getTransactionCount") do(data: EthAddressStr, quantityTag: string) -> HexQuantityStr:
    info "eth_getTransactionCount", data=data.string, quantityTag=quantityTag
    let
      address = data.toAddress
      accDB   = stateDBFromTag(quantityTag)
    result = encodeQuantity(accDB.getNonce(address))

  server.rpc("eth_getBlockTransactionCountByHash") do(data: EthHashStr) -> HexQuantityStr:
    info "eth_getBlockTransactionCountByHash", data=data.string
    let
      blockHash = data.toHash
      header    = chainDB.getBlockHeader(blockHash)
      txCount   = chainDB.getTransactionCount(header.txRoot)
    result = encodeQuantity(txCount.uint)

  server.rpc("eth_getBlockTransactionCountByNumber") do(quantityTag: string) -> HexQuantityStr:
    info "eth_getBlockTransactionCountByNumber", data=quantityTag
    let
      header  = chainDB.headerFromTag(quantityTag)
      txCount = chainDB.getTransactionCount(header.txRoot)
    result = encodeQuantity(txCount.uint)

  server.rpc("eth_getUncleCountByBlockHash") do(data: EthHashStr) -> HexQuantityStr:
    info "eth_getUncleCountByBlockHash", data=data.string
    let
      blockHash   = data.toHash
      header      = chainDB.getBlockHeader(blockHash)
      unclesCount = chainDB.getUnclesCount(header.ommersHash)
    result = encodeQuantity(unclesCount.uint)

  server.rpc("eth_getUncleCountByBlockNumber") do(quantityTag: string) -> HexQuantityStr:
    info "eth_getUncleCountByBlockNumber", quantityTag=quantityTag
    let
      header      = chainDB.headerFromTag(quantityTag)
      unclesCount = chainDB.getUnclesCount(header.ommersHash)
    result = encodeQuantity(unclesCount.uint)

  server.rpc("eth_getCode") do(data: EthAddressStr, quantityTag: string) -> HexDataStr:
    info "eth_getCode", quantityTag=quantityTag
    let
      accDB   = stateDBFromTag(quantityTag)
      address = data.toAddress
      storage = accDB.getCode(address)
    result = hexDataStr(storage)

  template sign(privateKey: PrivateKey, message: string): string =
    let msgData = "\x19Ethereum Signed Message:\n" & $message.len & message
    $sign(privateKey, msgData.toBytes())

  server.rpc("eth_sign") do(data: EthAddressStr, message: HexDataStr) -> HexDataStr:
    info "eth_sign", data=data.string
    let
      address = data.toAddress
      acc     = ctx.am.getAccount(address).tryGet()
      msg     = hexToSeqByte(message.string)

    if not acc.unlocked:
      raise newException(ValueError, "Account locked, please unlock it first")
    result = ("0x" & sign(acc.privateKey, cast[string](msg))).HexDataStr

  server.rpc("eth_signTransaction") do(data: TxSend) -> HexDataStr:
    info "eth_signTransaction", data=data
    let
      address = data.source.toAddress
      acc     = ctx.am.getAccount(address).tryGet()

    if not acc.unlocked:
      raise newException(ValueError, "Account locked, please unlock it first")

    let
      accDB    = stateDBFromTag("latest")
      tx       = unsignedTx(data, chainDB, accDB.getNonce(address) + 1)
      eip155   = com.isEIP155(com.syncCurrent)
      signedTx = signTransaction(tx, acc.privateKey, com.chainId, eip155)
      rlpTx    = rlp.encode(signedTx)

    result = hexDataStr(rlpTx)

  server.rpc("eth_sendTransaction") do(data: TxSend) -> EthHashStr:
    info "eth_sendTransaction", data=data
    let
      address = data.source.toAddress
      acc     = ctx.am.getAccount(address).tryGet()

    if not acc.unlocked:
      raise newException(ValueError, "Account locked, please unlock it first")

    let
      accDB    = stateDBFromTag("latest")
      tx       = unsignedTx(data, chainDB, accDB.getNonce(address) + 1)
      eip155   = com.isEIP155(com.syncCurrent)
      signedTx = signTransaction(tx, acc.privateKey, com.chainId, eip155)

    txPool.add(signedTx)
    result = rlpHash(signedTx).ethHashStr

  server.rpc("eth_sendRawTransaction") do(data: HexDataStr) -> EthHashStr:
    let
      txBytes = hexToSeqByte(data.string)
      signedTx = decodeTx(txBytes)

    # txPool.add(signedTx)
    let header = chainDB.headerFromTag("latest")
    var vmState = BaseVMState.new(header, com)
    let fork = vmState.com.toEVMFork(header.forkDeterminationInfoForHeader)

    var sender = signedTx.getSender()

    var balance = vmState.stateDB.getBalance(sender)
    let accTx = vmState.stateDB.beginSavepoint
    let gasBurned = signedTx.txCallEvm(sender, vmState, fork)
    vmState.stateDB.commit(accTx)

    result = rlpHash(signedTx).ethHashStr
    info "eth_sendRawTransaction", data=data.string, result=result.string, balance=balance, gasBurned=gasBurned

  server.rpc("eth_getTransactionByHash") do(data: EthHashStr) -> Option[TransactionObject]:
    info "eth_getTransactionByHash", data=data.string
    let txDetails = chainDB.getTransactionKey(data.toHash())
    if txDetails.index < 0:
      return none(TransactionObject)

    let header = chainDB.getBlockHeader(txDetails.blockNumber)
    info "eth_getTransactionByHash", header=header
    var tx: Transaction
    if chainDB.getTransaction(header.txRoot, txDetails.index, tx):
      result = some(populateTransactionObject(tx, header, txDetails.index))

  server.rpc("eth_call") do(call: EthCall, quantityTag: string) -> HexDataStr:
    info "eth_call", call=call, quantityTag=quantityTag
    let
      header   = headerFromTag(chainDB, quantityTag)
      callData = callData(call)
      res      = rpcCallEvm(callData, header, com)
    result = hexDataStr(res.output)

  proc eth_estimateGas(params: JsonNode): Future[StringOfJson] {.gcsafe.} =
    try:
      var to = if params[0].hasKey("to"): params[0]["to"].getStr() else : ""
      var call : EthCall
      if to == "":
        call = EthCall(source: some EthAddressStr params.elems[0]["from"].getStr, 
                            data: some EthHashStr params.elems[0]["data"].getStr)
      else:
         call = unpackArg(params, "call", type(EthCall))
      let header = chainDB.headerFromTag("latest")
      let callData = callData(call)
      let gasUsed = rpcEstimateGas(callData, header, com, DEFAULT_RPC_GAS_CAP)
      result = newFuture[StringOfJson]()
      result.complete StringOfJson $gasUsed
    
    except:
      echo getCurrentExceptionMsg()

  server.router.register("eth_estimateGas", eth_estimateGas)
  # server.rpc("eth_estimateGas") do(call: EthCall) -> HexQuantityStr:
  #   let
  #     header   = chainDB.headerFromTag("latest")
  #     callData = callData(call)
  #     gasUsed  = rpcEstimateGas(callData, header, com, DEFAULT_RPC_GAS_CAP)
  #   result = encodeQuantity(gasUsed.uint64)

  server.rpc("eth_getBlockByHash") do(data: EthHashStr, fullTransactions: bool) -> Option[BlockObject]:
    info "eth_getBlockByHash", data=data.string, fullTransactions=fullTransactions
    var
      header: BlockHeader
      hash = data.toHash

    if chainDB.getBlockHeader(hash, header):
      result = some populateBlockObject(header, chainDB, fullTransactions)
    else:
      result = none BlockObject

  server.rpc("eth_getBlockByNumber") do(quantityTag: string, fullTransactions: bool) -> Option[BlockObject]:
    try:
      let header = chainDB.headerFromTag(quantityTag)
      result = some(populateBlockObject(header, chainDB, fullTransactions))
    except CatchableError:
      result = none(BlockObject)
    # info "eth_getBlockByNumber", quantityTag=quantityTag, fullTransactions=fullTransactions,result=result


  server.rpc("eth_getTransactionByBlockHashAndIndex") do(data: EthHashStr, quantity: HexQuantityStr) -> Option[TransactionObject]:
    info "eth_getTransactionByBlockHashAndIndex", data=data.string
    let index  = hexToInt(quantity.string, int)
    var header: BlockHeader
    if not chainDB.getBlockHeader(data.toHash(), header):
      return none(TransactionObject)

    var tx: Transaction
    if chainDB.getTransaction(header.txRoot, index, tx):
      result = some(populateTransactionObject(tx, header, index))

  server.rpc("eth_getTransactionByBlockNumberAndIndex") do(quantityTag: string, quantity: HexQuantityStr) -> Option[TransactionObject]:
    info "eth_getTransactionByBlockNumberAndIndex", quantityTag=quantityTag,quantity=quantity.string
    let
      header = chainDB.headerFromTag(quantityTag)
      index  = hexToInt(quantity.string, int)

    var tx: Transaction
    if chainDB.getTransaction(header.txRoot, index, tx):
      result = some(populateTransactionObject(tx, header, index))

  server.rpc("eth_getTransactionReceipt") do(data: EthHashStr) -> Option[ReceiptObject]:
    info "eth_getTransactionReceipt", data=data.string
    let txDetails = chainDB.getTransactionKey(data.toHash())
    if txDetails.index < 0:
      return none(ReceiptObject)

    let header = chainDB.getBlockHeader(txDetails.blockNumber)
    var tx: Transaction
    if not chainDB.getTransaction(header.txRoot, txDetails.index, tx):
      return none(ReceiptObject)

    var
      idx = 0
      prevGasUsed = GasInt(0)
      fork = com.toEVMFork(header.forkDeterminationInfoForHeader)

    for receipt in chainDB.getReceipts(header.receiptRoot):
      let gasUsed = receipt.cumulativeGasUsed - prevGasUsed
      prevGasUsed = receipt.cumulativeGasUsed
      if idx == txDetails.index:
        return some(populateReceipt(receipt, gasUsed, tx, txDetails.index, header, fork))
      idx.inc

  server.rpc("eth_getUncleByBlockHashAndIndex") do(data: EthHashStr, quantity: HexQuantityStr) -> Option[BlockObject]:
    info "eth_getUncleByBlockHashAndIndex", data=data.string

    let index  = hexToInt(quantity.string, int)
    var header: BlockHeader
    if not chainDB.getBlockHeader(data.toHash(), header):
      return none(BlockObject)

    let uncles = chainDB.getUncles(header.ommersHash)
    if index < 0 or index >= uncles.len:
      return none(BlockObject)

    var uncle = populateBlockObject(uncles[index], chainDB, false, true)
    uncle.totalDifficulty = encodeQuantity(chainDB.getScore(header.hash))
    result = some(uncle)

  server.rpc("eth_getUncleByBlockNumberAndIndex") do(quantityTag: string, quantity: HexQuantityStr) -> Option[BlockObject]:
    info "eth_getUncleByBlockNumberAndIndex", quantityTag=quantityTag
    let
      index  = hexToInt(quantity.string, int)
      header = chainDB.headerFromTag(quantityTag)
      uncles = chainDB.getUncles(header.ommersHash)

    if index < 0 or index >= uncles.len:
      return none(BlockObject)

    var uncle = populateBlockObject(uncles[index], chainDB, false, true)
    uncle.totalDifficulty = encodeQuantity(chainDB.getScore(header.hash))
    result = some(uncle)

  proc getLogsForBlock(
      chain: ChainDBRef,
      hash: Hash256,
      header: BlockHeader,
      opts: FilterOptions): seq[FilterLog]
        {.gcsafe, raises: [RlpError,ValueError].} =
    if headerBloomFilter(header, opts.address, opts.topics):
      let blockBody = chain.getBlockBody(hash)
      let receipts = chain.getReceipts(header.receiptRoot)

      let logs = deriveLogs(header, blockBody.transactions, receipts)
      let filteredLogs = filterLogs(logs, opts.address, opts.topics)
      return filteredLogs
    else:
      return @[]

  proc getLogsForRange(
      chain: ChainDBRef,
      start: UInt256,
      finish: UInt256,
      opts: FilterOptions): seq[FilterLog]
        {.gcsafe, raises: [RlpError,ValueError].} =
    var logs = newSeq[FilterLog]()
    var i = start
    while i <= finish:
      let res = chain.getBlockHeaderWithHash(i)
      if res.isSome():
        let (hash, header)= res.unsafeGet()
        let filtered = chain.getLogsForBlock(header, hash, opts)
        logs.add(filtered)
      else:
        #
        return logs
      i = i + 1
    return logs

  server.rpc("eth_getLogs") do(filterOptions: FilterOptions) -> seq[FilterLog]:
    if filterOptions.blockHash.isSome():
      let hash = filterOptions.blockHash.unsafeGet()
      let header = chainDB.getBlockHeader(hash)
      return getLogsForBlock(chainDB, hash, header, filterOptions)
    else:

      let fromHeader = chainDB.headerFromTag(filterOptions.fromBlock)
      let toHeader = chainDB.headerFromTag(filterOptions.fromBlock)

      let logs = chainDB.getLogsForRange(
        fromHeader.blockNumber,
        toHeader.blockNumber,
        filterOptions
      )
      return logs

#[
  server.rpc("eth_newFilter") do(filterOptions: FilterOptions) -> int:
    ## Creates a filter object, based on filter options, to notify when the state changes (logs).
    ## To check if the state has changed, call eth_getFilterChanges.
    ## Topics are order-dependent. A transaction with a log with topics [A, B] will be matched by the following topic filters:
    ## [] "anything"
    ## [A] "A in first position (and anything after)"
    ## [null, B] "anything in first position AND B in second position (and anything after)"
    ## [A, B] "A in first position AND B in second position (and anything after)"
    ## [[A, B], [A, B]] "(A OR B) in first position AND (A OR B) in second position (and anything after)"
    ##
    ## filterOptions: settings for this filter.
    ## Returns integer filter id.
    discard

  server.rpc("eth_newBlockFilter") do() -> int:
    ## Creates a filter in the node, to notify when a new block arrives.
    ## To check if the state has changed, call eth_getFilterChanges.
    ##
    ## Returns integer filter id.
    discard

  server.rpc("eth_newPendingTransactionFilter") do() -> int:
    ## Creates a filter in the node, to notify when a new block arrives.
    ## To check if the state has changed, call eth_getFilterChanges.
    ##
    ## Returns integer filter id.
    discard

  server.rpc("eth_uninstallFilter") do(filterId: int) -> bool:
    ## Uninstalls a filter with given id. Should always be called when watch is no longer needed.
    ## Additonally Filters timeout when they aren't requested with eth_getFilterChanges for a period of time.
    ##
    ## filterId: The filter id.
    ## Returns true if the filter was successfully uninstalled, otherwise false.
    discard

  server.rpc("eth_getFilterChanges") do(filterId: int) -> seq[FilterLog]:
    ## Polling method for a filter, which returns an list of logs which occurred since last poll.
    ##
    ## filterId: the filter id.
    result = @[]

  server.rpc("eth_getFilterLogs") do(filterId: int) -> seq[FilterLog]:
    ## filterId: the filter id.
    ## Returns a list of all logs matching filter with given id.
    result = @[]

  server.rpc("eth_getWork") do() -> array[3, UInt256]:
    ## Returns the hash of the current block, the seedHash, and the boundary condition to be met ("target").
    ## Returned list has the following properties:
    ## DATA, 32 Bytes - current block header pow-hash.
    ## DATA, 32 Bytes - the seed hash used for the DAG.
    ## DATA, 32 Bytes - the boundary condition ("target"), 2^256 / difficulty.
    discard

  server.rpc("eth_submitWork") do(nonce: int64, powHash: HexDataStr, mixDigest: HexDataStr) -> bool:
    ## Used for submitting a proof-of-work solution.
    ##
    ## nonce: the nonce found.
    ## headerPow: the header's pow-hash.
    ## mixDigest: the mix digest.
    ## Returns true if the provided solution is valid, otherwise false.
    discard

  server.rpc("eth_submitHashrate") do(hashRate: HexDataStr, id: HexDataStr) -> bool:
    ## Used for submitting mining hashrate.
    ##
    ## hashRate: a hexadecimal string representation (32 bytes) of the hash rate.
    ## id: a random hexadecimal(32 bytes) ID identifying the client.
    ## Returns true if submitting went through succesfully and false otherwise.
    discard]#
