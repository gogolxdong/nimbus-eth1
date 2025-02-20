import
  math,
  ../../common/common,
  ../../constants,
  ../../db/accounts_cache,
  ../../transaction,
  ../../utils/utils,
  ../../vm_state,
  ../../vm_types,
  ../../utils/debug,
  ../clique,
  ../dao,
  ./calculate_reward,
  ./executor_helpers,
  ./process_transaction,
  chronicles,
  stew/results

{.push raises: [].}

# ------------------------------------------------------------------------------
# Private functions
# ------------------------------------------------------------------------------

func gwei(n: uint64): UInt256 =
  n.u256 * (10 ^ 9).u256

proc processTransactions*(vmState: BaseVMState; header: BlockHeader; transactions: seq[Transaction]): Result[void, string] {.gcsafe, raises: [CatchableError].} =
  vmState.receipts = newSeq[Receipt](transactions.len)
  vmState.cumulativeGasUsed = 0
  for txIndex, tx in transactions:
    var sender: EthAddress
    if not tx.getSender(sender):
      let debugTx =tx.debug()
      return err("Could not get sender for tx with index " & $(txIndex) & ": " & debugTx)
    let rc = vmState.processTransaction(tx, sender, header)
    if rc.isErr:
      let debugTx =tx.debug()
      return err("Error processing tx with index " & $(txIndex) & ":\n" & debugTx & "\n" & rc.error)
    vmState.receipts[txIndex] = vmState.makeReceipt(tx.txType)
  ok()

proc procBlkPreamble(vmState: BaseVMState; header: BlockHeader; body: BlockBody): bool {.gcsafe, raises: [CatchableError].} =

  # if vmState.com.daoForkSupport and vmState.com.daoForkBlock.get == header.blockNumber:
  #   vmState.mutateStateDB:
  #     db.applyDAOHardFork()

  if body.transactions.calcTxRoot != header.txRoot:
    debug "Mismatched txRoot", blockNumber = header.blockNumber
    return false

  if header.txRoot != EMPTY_ROOT_HASH:
    if body.transactions.len == 0:
      info "No transactions in body", blockNumber = header.blockNumber
      return false
    else:
      let r = processTransactions(vmState, header, body.transactions)
      if r.isErr:
        error("error in processing transactions", err=r.error)

  # if vmState.determineFork >= FkShanghai:
  #   if header.withdrawalsRoot.isNone:
  #     raise ValidationError.newException("Post-Shanghai block header must have withdrawalsRoot")
  #   if body.withdrawals.isNone:
  #     raise ValidationError.newException("Post-Shanghai block body must have withdrawals")

  #   for withdrawal in body.withdrawals.get:
  #     vmState.stateDB.addBalance(withdrawal.address, withdrawal.amount.gwei)
  # else:
  #   if header.withdrawalsRoot.isSome:
  #     raise ValidationError.newException("Pre-Shanghai block header must not have withdrawalsRoot")
  #   if body.withdrawals.isSome:
  #     raise ValidationError.newException("Pre-Shanghai block body must not have withdrawals")

  # if vmState.cumulativeGasUsed != header.gasUsed:
  #   info "gasUsed neq cumulativeGasUsed", gasUsed = header.gasUsed, cumulativeGasUsed = vmState.cumulativeGasUsed 
  #   return false

  if header.ommersHash != EMPTY_UNCLE_HASH:
    let h = vmState.com.db.persistUncles(body.uncles)
    if h != header.ommersHash: 
      info "Uncle hash mismatch"
      return false

  true

proc procBlkEpilogue(vmState: BaseVMState;
                     header: BlockHeader; body: BlockBody): bool
    {.gcsafe, raises: [RlpError].} =
  # Reward beneficiary
  # vmState.mutateStateDB:
  #   if vmState.generateWitness:
  #     db.collectWitnessData()
  #   let clearEmptyAccount = vmState.determineFork >= FkSpurious
  #   db.persist(clearEmptyAccount, ClearCache in vmState.flags)

  let stateDb = vmState.stateDB
  if header.stateRoot != stateDb.rootHash:
    info "wrong state root in block", blockNumber = header.blockNumber, expected = header.stateRoot, actual = stateDb.rootHash, arrivedFrom = vmState.com.db.getCanonicalHead().stateRoot
    return false

  let bloom = createBloom(vmState.receipts)
  if header.bloom != bloom:
    info "wrong bloom in block", blockNumber = header.blockNumber
    return false

  let receiptRoot = calcReceiptRoot(vmState.receipts)
  if header.receiptRoot != receiptRoot:
    info "wrong receiptRoot in block", blockNumber = header.blockNumber, actual = receiptRoot, expected = header.receiptRoot
    return false

  true

# ------------------------------------------------------------------------------
# Public functions
# ------------------------------------------------------------------------------

proc processBlockNotPoA*(vmState: BaseVMState; header:  BlockHeader; body:    BlockBody): ValidationResult {.gcsafe, raises: [CatchableError].} =
  
  if vmState.com.consensus == ConsensusType.POA:
    info "Unsupported PoA request"
    return ValidationResult.Error

  var dbTx = vmState.com.db.db.beginTransaction()
  defer: dbTx.dispose()

  if not vmState.procBlkPreamble(header, body):
    error "procBlkPreamble", blockNumber= header.blockNumber
    return ValidationResult.Error

  # EIP-3675: no reward for miner in POA/POS
  # if vmState.com.consensus == ConsensusType.POW:
  #   vmState.calculateReward(header, body)

  if not vmState.procBlkEpilogue(header, body):
    error "procBlkEpilogue", blockNumber= header.blockNumber
    return ValidationResult.Error

  dbTx.commit(applyDeletes = false)

  ValidationResult.OK


proc processBlock*(
    vmState: BaseVMState;  ## Parent environment of header/body block
    poa:     Clique;       ## PoA descriptor (if needed, at all)
    header:  BlockHeader;  ## Header/body block to add to the blockchain
    body:    BlockBody): ValidationResult
    {.gcsafe, raises: [CatchableError].} =
  ## Generalised function to processes `(header,body)` pair for any network,
  ## regardless of PoA or not. Currently there is no mining support so this
  ## function is mostly the same as `processBlockNotPoA()`.
  ##
  ## Rather than calculating the PoA state change here, it is done with the
  ## verification in the `chain/persist_blocks.persistBlocks()` method. So
  ## the `poa` descriptor is currently unused and only provided for later
  ## implementations (but can be savely removed, as well.)
  ## variant of `processBlock()` where the `header` argument is explicitely set.
  ##
  # # Process PoA state transition first so there is no need to re-wind on
  # # an error.
  # if vmState.chainDB.config.poaEngine and
  #    not poa.updatePoaState(header, body):
  #   debug "PoA update failed"
  #   return ValidationResult.Error

  var dbTx = vmState.com.db.db.beginTransaction()
  defer: dbTx.dispose()

  if not vmState.procBlkPreamble(header, body):
    return ValidationResult.Error

  # EIP-3675: no reward for miner in POA/POS
  if vmState.com.consensus == ConsensusType.POW:
    vmState.calculateReward(header, body)

  if not vmState.procBlkEpilogue(header, body):
    return ValidationResult.Error

  dbTx.commit(applyDeletes = false)

  ValidationResult.OK

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
