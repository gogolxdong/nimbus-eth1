{.push raises: [].}

import
  std/strutils,
  ../../common/common,
  ../../db/accounts_cache,
  ../../transaction/call_evm,
  ../../transaction,
  ../../vm_state,
  ../../vm_types,
  ../../evm/async/operations,
  ../validate,
  chronos, chronicles,
  stew/results

proc eip1559BaseFee(header: BlockHeader; fork: EVMFork): UInt256 =
  if FkLondon <= fork:
    result = header.baseFee

proc commitOrRollbackDependingOnGasUsed(vmState: BaseVMState, accTx: SavePoint,header: BlockHeader, tx: Transaction,gasBurned: GasInt, priorityFee: GasInt): Result[GasInt, string] {.raises: [].} =
  if header.gasLimit < vmState.cumulativeGasUsed + gasBurned:
    try:
      vmState.stateDB.rollback(accTx)
      return err("invalid tx: block header gasLimit reached. gasLimit=$1, gasUsed=$2, addition=$3" % [
        $header.gasLimit, $vmState.cumulativeGasUsed, $gasBurned])
    except ValueError as ex:
      return err(ex.msg)
  else:
    vmState.stateDB.commit(accTx)
    vmState.stateDB.addBalance(vmState.coinbase(), gasBurned.u256 * priorityFee.u256)
    vmState.cumulativeGasUsed += gasBurned

    vmState.gasPool += tx.gasLimit - gasBurned
    return ok(gasBurned)

proc asyncProcessTransactionImpl(
    vmState: BaseVMState; ## Parent accounts environment for transaction
    tx:      Transaction; ## Transaction to validate
    sender:  EthAddress;  ## tx.getSender or tx.ecRecover
    header:  BlockHeader; ## Header for the block containing the current tx
    fork:    EVMFork): Future[Result[GasInt, string]]
    {.async, gcsafe.} =

  let
    roDB = vmState.readOnlyStateDB
    baseFee256 = header.eip1559BaseFee(fork)
    baseFee = baseFee256.truncate(GasInt)
    tx = eip1559TxNormalization(tx, baseFee, fork)
    priorityFee = min(tx.maxPriorityFee, tx.maxFee - baseFee)
    excessDataGas = 0'u64

  var res: Result[GasInt, string] = err("")

  await ifNecessaryGetAccounts(vmState, @[sender, vmState.coinbase()])
  if tx.to.isSome:
    await ifNecessaryGetCode(vmState, tx.to.get)

  if vmState.gasPool < tx.gasLimit:
    return err("gas limit reached. gasLimit=$1, gasNeeded=$2" % [$vmState.gasPool, $tx.gasLimit])

  vmState.gasPool -= tx.gasLimit


  let txRes = roDB.validateTransaction(tx, sender, header.gasLimit, baseFee256, excessDataGas, fork)
  if txRes.isOk:
    vmState.stateDB.clearTransientStorage()

    let
      accTx = vmState.stateDB.beginSavepoint
      gasBurned = tx.txCallEvm(sender, vmState, fork)
    res = commitOrRollbackDependingOnGasUsed(vmState, accTx, header, tx, gasBurned, priorityFee)
  else:
    res = err(txRes.error)

  if vmState.generateWitness:
    vmState.stateDB.collectWitnessData()
  vmState.stateDB.persist(clearEmptyAccount = true, clearCache = false)

  return res

# ------------------------------------------------------------------------------
# Public functions
# ------------------------------------------------------------------------------

proc asyncProcessTransaction*(
    vmState: BaseVMState; ## Parent accounts environment for transaction
    tx:      Transaction; ## Transaction to validate
    sender:  EthAddress;  ## tx.getSender or tx.ecRecover
    header:  BlockHeader; ## Header for the block containing the current tx
    fork:    EVMFork): Future[Result[GasInt,string]]
    {.async, gcsafe.} =
  ## Process the transaction, write the results to accounts db. The function
  ## returns the amount of gas burned if executed.
  return await vmState.asyncProcessTransactionImpl(tx, sender, header, fork)

# FIXME-duplicatedForAsync
proc asyncProcessTransaction*(
    vmState: BaseVMState; ## Parent accounts environment for transaction
    tx:      Transaction; ## Transaction to validate
    sender:  EthAddress;  ## tx.getSender or tx.ecRecover
    header:  BlockHeader): Future[Result[GasInt,string]]
    {.async, gcsafe.} =
  ## Variant of `asyncProcessTransaction()` with `*fork* derived
  ## from the `vmState` argument.
  let fork = vmState.com.toEVMFork(header.forkDeterminationInfoForHeader)
  return await vmState.asyncProcessTransaction(tx, sender, header, fork)

proc processTransaction*(
    vmState: BaseVMState; ## Parent accounts environment for transaction
    tx:      Transaction; ## Transaction to validate
    sender:  EthAddress;  ## tx.getSender or tx.ecRecover
    header:  BlockHeader; ## Header for the block containing the current tx
    fork:    EVMFork): Result[GasInt,string]
    {.gcsafe, raises: [CatchableError].} =
  return waitFor(vmState.asyncProcessTransaction(tx, sender, header, fork))

proc processTransaction*(
    vmState: BaseVMState; ## Parent accounts environment for transaction
    tx:      Transaction; ## Transaction to validate
    sender:  EthAddress;  ## tx.getSender or tx.ecRecover
    header:  BlockHeader): Result[GasInt,string]
    {.gcsafe, raises: [CatchableError].} =
  return waitFor(vmState.asyncProcessTransaction(tx, sender, header))

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
