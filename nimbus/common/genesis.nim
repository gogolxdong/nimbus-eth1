import
  chronicles,
  std/tables,
  eth/[common, rlp, eip1559],
  eth/trie/[db, trie_defs],
  ../db/state_db,
  ../constants,
  ./chain_config

{.push raises: [].}

# ------------------------------------------------------------------------------
# Public functions
# ------------------------------------------------------------------------------
proc newStateDB*(
    db: TrieDatabaseRef;
    pruneTrie: bool;
      ): AccountStateDB
      {.gcsafe, raises: [].}=
  newAccountStateDB(db, emptyRlpHash, pruneTrie)

proc toGenesisHeader*(
    g: Genesis;
    sdb: AccountStateDB;
    fork: HardFork;
      ): BlockHeader
      {.gcsafe, raises: [RlpError].} =
  sdb.db.put(emptyRlpHash.data, emptyRlp)

  for address, account in g.alloc:
    # info "toGenesisHeader", address=address, account=account
    sdb.setAccount(address, newAccount(account.nonce, account.balance))
    sdb.setCode(address, account.code)

    if sdb.pruneTrie and 0 < account.storage.len:
      sdb.db.put(emptyRlpHash.data, emptyRlp) # <-- kludge

    for k, v in account.storage:
      sdb.setStorage(address, k, v)

  # info "toGenesisHeader", coinbase=g.coinbase
  result = BlockHeader(
    nonce: g.nonce,
    timestamp: g.timestamp,
    extraData: g.extraData,
    gasLimit: g.gasLimit,
    difficulty: g.difficulty,
    mixDigest: g.mixHash,
    coinbase: g.coinbase,
    stateRoot: sdb.rootHash,
    parentHash: GENESIS_PARENT_HASH,
    txRoot: EMPTY_ROOT_HASH,
    receiptRoot: EMPTY_ROOT_HASH,
    ommersHash: EMPTY_UNCLE_HASH
  )
  info "toGenesisHeader", header=result
  # if g.baseFeePerGas.isSome:
  #   result.baseFee = g.baseFeePerGas.get()
  # elif fork >= London:
  #   result.baseFee = EIP1559_INITIAL_BASE_FEE.u256

  if g.gasLimit == 0.GasInt:
    result.gasLimit = GENESIS_GAS_LIMIT

  if g.difficulty.isZero and fork <= London:
    result.difficulty = GENESIS_DIFFICULTY

  # if fork >= Shanghai:
  #   result.withdrawalsRoot = some(EMPTY_ROOT_HASH)

  # if fork >= Cancun:
  #   result.dataGasUsed = g.dataGasUsed
  #   result.excessDataGas = g.excessDataGas

proc toGenesisHeader*(
    genesis: Genesis;
    fork: HardFork;
    db = TrieDatabaseRef(nil);
      ): BlockHeader
      {.gcsafe, raises: [RlpError].} =
  ## Generate the genesis block header from the `genesis` and `config` argument value.
  let
    db  = if db.isNil: newMemoryDB() else: db
    sdb = newStateDB(db, pruneTrie = true)
  toGenesisHeader(genesis, sdb, fork)

proc toGenesisHeader*(
    params: NetworkParams;
    db = TrieDatabaseRef(nil);
      ): BlockHeader
      {.raises: [RlpError].} =
  ## Generate the genesis block header from the `genesis` and `config` argument value.
  let map  = toForkTransitionTable(params.config)
  let fork = map.toHardFork(forkDeterminationInfo(0.toBlockNumber, params.genesis.timestamp.fromUnix))
  toGenesisHeader(params.genesis, fork, db)

# End



# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
