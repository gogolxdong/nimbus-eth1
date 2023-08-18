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
# parentHash: 0000000000000000000000000000000000000000000000000000000000000000, 
# ommersHash: 1DCC4DE8DEC75D7AAB85B567B6CCD41AD312451B948A7413F0A142FD40D49347, 
# coinbase: 0000000000000000000000000000000000000000, 
# stateRoot: 56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421, 
# txRoot: 56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421, 
# receiptRoot: 56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421, 
# bloom: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 
# difficulty: 1, 
# blockNumber: 0, 
# gasLimit: 40000000, 
# gasUsed: 0, 
# timestamp: 1587390414, 
# extraData: @[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 42, 124, 221, 149, 155, 254, 141, 148, 135, 178, 164, 59, 51, 86, 82, 149, 166, 152, 247, 226, 100, 136, 170, 77, 25, 85, 238, 51, 64, 63, 140, 203, 29, 77, 229, 251, 151, 199, 173, 226, 158, 249, 244, 54, 12, 96, 108, 122, 180, 219, 38, 176, 22, 0, 125, 58, 208, 171, 134, 160, 238, 1, 195, 177, 40, 58, 160, 103, 197, 142, 171, 71, 9, 248, 94, 153, 212, 109, 229, 254, 104, 91, 29, 237, 128, 19, 120, 93, 102, 35, 204, 24, 210, 20, 50, 11, 107, 182, 71, 89, 120, 243, 173, 252, 113, 156, 153, 103, 76, 7, 33, 102, 112, 133, 137, 3, 62, 45, 154, 254, 194, 190, 78, 194, 2, 83, 184, 100, 33, 97, 188, 63, 68, 79, 83, 103, 156, 31, 61, 71, 47, 123, 232, 54, 28, 128, 164, 193, 231, 233, 170, 240, 1, 208, 135, 127, 28, 253, 226, 24, 206, 47, 215, 84, 78, 11, 44, 201, 70, 146, 212, 167, 4, 222, 190, 247, 188, 182, 19, 40, 184, 247, 22, 100, 150, 153, 106, 125, 162, 28, 241, 241, 176, 77, 155, 62, 38, 163, 208, 119, 45, 76, 64, 123, 190, 73, 67, 142, 216, 89, 254, 150, 91, 20, 13, 207, 26, 171, 113, 169, 107, 186, 215, 207, 52, 181, 250, 81, 29, 142, 150, 61, 187, 162, 136, 177, 150, 14, 117, 214, 68, 48, 179, 35, 2, 148, 209, 44, 106, 178, 170, 197, 194, 205, 104, 232, 11, 22, 181, 129, 234, 10, 110, 60, 81, 27, 189, 16, 244, 81, 158, 206, 55, 220, 36, 136, 126, 17, 181, 93, 122, 226, 245, 185, 227, 134, 205, 27, 80, 164, 85, 6, 150, 217, 87, 203, 73, 0, 240, 58, 130, 1, 39, 8, 218, 252, 158, 27, 136, 15, 208, 131, 179, 33, 130, 184, 105, 190, 142, 9, 34, 184, 31, 142, 23, 95, 253, 229, 77, 121, 127, 225, 30, 176, 63, 158, 59, 247, 95, 29, 104, 191, 11, 139, 111, 180, 227, 23, 160, 249, 214, 240, 62, 175, 140, 230, 103, 91, 198, 13, 140, 77, 144, 130, 156, 232, 247, 45, 1, 99, 193, 213, 207, 52, 138, 134, 45, 85, 6, 48, 53, 231, 160, 37, 244, 218, 150, 141, 231, 228, 215, 228, 0, 65, 151, 145, 127, 64, 112, 241, 214, 202, 160, 43, 190, 186, 235, 181, 215, 229, 129, 228, 182, 101, 89, 230, 53, 248, 5, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 
# mixDigest: 0000000000000000000000000000000000000000000000000000000000000000, 
# nonce: [0, 0, 0, 0, 0, 0, 0, 0], 
# fee: none(UInt256)

# {
#   difficulty: 1,
#   extraData: "0x00000000000000000000000000000000000000000000000000000000000000002a7cdd959bfe8d9487b2a43b33565295a698f7e26488aa4d1955ee33403f8ccb1d4de5fb97c7ade29ef9f4360c606c7ab4db26b016007d3ad0ab86a0ee01c3b1283aa067c58eab4709f85e99d46de5fe685b1ded8013785d6623cc18d214320b6bb6475978f3adfc719c99674c072166708589033e2d9afec2be4ec20253b8642161bc3f444f53679c1f3d472f7be8361c80a4c1e7e9aaf001d0877f1cfde218ce2fd7544e0b2cc94692d4a704debef7bcb61328b8f7166496996a7da21cf1f1b04d9b3e26a3d0772d4c407bbe49438ed859fe965b140dcf1aab71a96bbad7cf34b5fa511d8e963dbba288b1960e75d64430b3230294d12c6ab2aac5c2cd68e80b16b581ea0a6e3c511bbd10f4519ece37dc24887e11b55d7ae2f5b9e386cd1b50a4550696d957cb4900f03a82012708dafc9e1b880fd083b32182b869be8e0922b81f8e175ffde54d797fe11eb03f9e3bf75f1d68bf0b8b6fb4e317a0f9d6f03eaf8ce6675bc60d8c4d90829ce8f72d0163c1d5cf348a862d55063035e7a025f4da968de7e4d7e4004197917f4070f1d6caa02bbebaebb5d7e581e4b66559e635f805ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
#   gasLimit: 40000000,
#   gasUsed: 0,
#   hash: "0x0d21840abff46b96c84b2ac9e10e4f5cdaeb5693cb665db62a2f3b02d2d57b5b",
#   logsBloom: "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
#   miner: "0xfffffffffffffffffffffffffffffffffffffffe",
#   mixHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
#   nonce: "0x0000000000000000",
#   number: 0,
#   parentHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
#   receiptsRoot: "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
#   sha3Uncles: "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
#   size: 1028,
#   stateRoot: "0x919fcc7ad870b53db0aa76eb588da06bacb6d230195100699fc928511003b422",
#   timestamp: 1587390414,
#   totalDifficulty: 1,
#   transactions: [],
#   transactionsRoot: "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
#   uncles: []
# }
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


  info "toGenesisHeader", timestamp=g.timestamp
  result = BlockHeader(
    nonce: g.nonce,
    timestamp: 1587390414,
    extraData: g.extraData,
    gasLimit: g.gasLimit,
    difficulty: g.difficulty,
    mixDigest: g.mixHash,
    coinbase: g.coinbase,
    # stateRoot: sdb.rootHash,
    stateRoot: Hash256.fromHex"0x919fcc7ad870b53db0aa76eb588da06bacb6d230195100699fc928511003b422",
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
