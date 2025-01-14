# Nimbus
# Copyright (c) 2018-2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

import
  chronicles,
  chronos,
  eth/common/eth_types,
  ../constants,
  ../db/accounts_cache,
  ../transaction,
  ./computation,
  ./interpreter_dispatch,
  ./interpreter/gas_costs,
  ./message,
  ./state,
  ./types

{.push raises: [].}

proc setupTxContext*(vmState: BaseVMState,
                     origin: EthAddress,
                     gasPrice: GasInt,
                     versionedHashes: openArray[VersionedHash],
                     forkOverride=none(EVMFork)) =
  ## this proc will be called each time a new transaction
  ## is going to be executed
  vmState.txOrigin = origin
  vmState.txGasPrice = gasPrice
  vmState.fork =
    if forkOverride.isSome:
      forkOverride.get
    else:
      vmState.determineFork
  vmState.gasCosts = vmState.fork.forkToSchedule
  vmState.txVersionedHashes = @versionedHashes

# FIXME-awkwardFactoring: the factoring out of the pre and
# post parts feels awkward to me, but for now I'd really like
# not to have too much duplicated code between sync and async.
# --Adam

proc preExecComputation*(c: Computation) =
  if not c.msg.isCreate:
    c.vmState.mutateStateDB:
      db.incNonce(c.msg.sender)

proc postExecComputation*(c: Computation) =
  if c.isSuccess:
    if c.fork < FkLondon:
      # EIP-3529: Reduction in refunds
      c.refundSelfDestruct()
  c.vmState.status = c.isSuccess

proc execComputation*(c: Computation) {.gcsafe, raises: [CatchableError].} =
  c.preExecComputation()
  c.execCallOrCreate()
  c.postExecComputation()

# FIXME-duplicatedForAsync
proc asyncExecComputation*(c: Computation): Future[void] {.async.} =
  # info "asyncExecComputation", state=c.vmState, code=c.code.bytes.len
  c.preExecComputation()
  await c.asyncExecCallOrCreate()
  c.postExecComputation()
