{.push raises: [].}

import
  sequtils,
  ../../vm_state,
  ../../vm_types,
  ../clique/clique_verify,
  ../clique,
  ../executor,
  ../validate,
  ./chain_desc,
  chronicles,
  stint

when not defined(release):
  import
    ../../tracer,
    ../../utils/utils

type
  PersistBlockFlag = enum
    NoPersistHeader
    NoSaveTxs
    NoSaveReceipts
    NoSaveWithdrawals

  PersistBlockFlags = set[PersistBlockFlag]

# ------------------------------------------------------------------------------
# Private
# ------------------------------------------------------------------------------

proc persistBlocksImpl(c: ChainRef; headers: openArray[BlockHeader];bodies: openArray[BlockBody], flags: PersistBlockFlags = {}): ValidationResult {.inline, raises: [CatchableError].} =

  let transaction = if c.com.forked : c.com.forkDB.beginTransaction() else: c.db.db.beginTransaction()
  defer: transaction.dispose()

  var cliqueState = c.clique.cliqueSave
  defer: c.clique.cliqueRestore(cliqueState)

  c.com.hardForkTransition(headers[0])

  # Note that `0 < headers.len`, assured when called from `persistBlocks()`
  let vmState = BaseVMState()
  if not vmState.init(headers[0], c.com):
    info "Cannot initialise VmState", fromBlock = headers[0].blockNumber, toBlock = headers[^1].blockNumber
    return ValidationResult.Error

  # info "Persisting blocks", fromBlock = headers[0].blockNumber, toBlock = headers[^1].blockNumber, headerHash = headers.mapIt(it.blockHash)

  for i in 0 ..< headers.len:
    let
      (header, body) = (headers[i], bodies[i])

    c.com.hardForkTransition(header)

    if not vmState.reinit(header):
      error "Cannot update VmState", blockNumber = header.blockNumber, item = i
      return ValidationResult.Error

    let
      validationResult = if c.validateBlock:
                           vmState.processBlock(c.clique, header, body)
                         else:
                           ValidationResult.OK
    when not defined(release):
      if validationResult == ValidationResult.Error and body.transactions.calcTxRoot == header.txRoot:
        dumpDebuggingMetaData(c.com, header, body, vmState)
        warn "Validation error. Debugging metadata dumped."

    if validationResult != ValidationResult.OK:
      return validationResult

    if c.validateBlock and c.extraValidation and c.verifyFrom <= header.blockNumber:
      if c.com.consensus == ConsensusType.POA:
        var parent = if 0 < i: @[headers[i-1]] else: @[]
        let rc = c.clique.cliqueVerify(c.com, header,parent)
        if rc.isOk:
          # mark it off so it would not auto-restore previous state
          c.clique.cliqueDispose(cliqueState)
        else:
          info "PoA header verification failed", blockNumber = header.blockNumber, msg = $rc.error
          return ValidationResult.Error
      else:
        let res = c.com.validateHeaderAndKinship(header,body,checkSealOK = false) # TODO: how to checkseal from here
        if res.isErr:
          info "block validation error", msg = res.error
          return ValidationResult.Error

    if NoPersistHeader notin flags:
      # discard c.db.persistHeaderToDb(header, c.com.consensus == ConsensusType.POS, c.com.startOfHistory)
      if c.com.forked:
        discard c.com.forkDB.ChainDBRef.persistHeaderToDb(header, c.com.consensus == ConsensusType.POA, if header.parentHash == Hash256(): c.com.startOfHistory else: header.parentHash)
      else:
        discard c.db.persistHeaderToDb(header, c.com.consensus == ConsensusType.POA, if header.parentHash == Hash256(): c.com.startOfHistory else: header.parentHash)

    if NoSaveTxs notin flags:
      if c.com.forked:
        discard c.com.forkDB.ChainDBRef.persistTransactions(header.blockNumber, body.transactions)
      else:
        discard c.db.persistTransactions(header.blockNumber, body.transactions)

    if NoSaveReceipts notin flags:
      if c.com.forked:
        discard c.com.forkDB.ChainDBRef.persistReceipts(vmState.receipts)
      else:
        discard c.db.persistReceipts(vmState.receipts)

    # if NoSaveWithdrawals notin flags and body.withdrawals.isSome:
    #   discard c.db.persistWithdrawals(body.withdrawals.get)

    c.com.syncCurrent = header.blockNumber

  transaction.commit()


# ------------------------------------------------------------------------------
# Public `ChainDB` methods
# ------------------------------------------------------------------------------

proc insertBlockWithoutSetHead*(c: ChainRef, header: BlockHeader,
                                body: BlockBody): ValidationResult
                                {.gcsafe, raises: [CatchableError].} =
  result = c.persistBlocksImpl(
    [header], [body], {NoPersistHeader, NoSaveReceipts})
  if result == ValidationResult.OK:
    c.db.persistHeaderToDbWithoutSetHead(header, c.com.startOfHistory)

proc setCanonical*(c: ChainRef, header: BlockHeader): ValidationResult {.gcsafe, raises: [CatchableError].} =
  if header.parentHash == Hash256():
    if c.com.forked:
      discard c.forkDB.setHead(header.blockHash)
    else:
      discard c.db.setHead(header.blockHash)
    return ValidationResult.OK

  var body: BlockBody
  if c.com.forked:
    if not c.forkDB.getBlockBody(header, body):
      debug "Failed to get BlockBody", hash = header.blockHash
      return ValidationResult.Error
  else:
    if not c.db.getBlockBody(header, body):
      debug "Failed to get BlockBody", hash = header.blockHash
      return ValidationResult.Error

  result = c.persistBlocksImpl([header], [body], {NoPersistHeader, NoSaveTxs})
  if result == ValidationResult.OK:
    if c.com.forked:
      discard c.forkDB.setHead(header.blockHash)
    else:
      discard c.db.setHead(header.blockHash)

proc setCanonical*(c: ChainRef, blockHash: Hash256): ValidationResult {.gcsafe, raises: [CatchableError].} =
  var header: BlockHeader
  if c.com.forked:
    if not c.forkDB.getBlockHeader(blockHash, header):
      info "Failed to get BlockHeader", hash = blockHash
      return ValidationResult.Error
  else:
    if not c.db.getBlockHeader(blockHash, header):
      info "Failed to get BlockHeader", hash = blockHash
      return ValidationResult.Error

  setCanonical(c, header)

proc persistBlocks*(c: ChainRef; headers: openArray[BlockHeader];
                      bodies: openArray[BlockBody]): ValidationResult
                        {.gcsafe, raises: [CatchableError].} =
  if headers.len != bodies.len:
    info "Number of headers not matching number of bodies"
    return ValidationResult.Error

  if headers.len == 0:
    info "Nothing to do"
    return ValidationResult.OK

  c.persistBlocksImpl(headers,bodies)

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
