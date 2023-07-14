

import
  ../constants,
  ./keyed_queue/kq_rlp,
  ./utils_defs,
  eth/[common, common/transaction, keys, rlp],
  stew/[keyed_queue, results],
  stint, chronicles

export
  utils_defs, results

{.push raises: [].}

logScope:
  topics = "ec_recover"

const
  INMEMORY_SIGNATURES* = ##\
    ## Default number of recent block signatures to keep in memory
    4096

type
  EcKey* = ##\
    array[32,byte]

  EcAddrResult* = ##\
    Result[EthAddress,UtilsError]

  EcRecover* = object
    size: uint
    q: KeyedQueue[EcKey,EthAddress]

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

proc vrsSerialised(tx: Transaction): Result[array[65,byte],UtilsError] =
  ## Parts copied from `transaction.getSignature`.
  var data: array[65,byte]
  data[0..31] = tx.R.toByteArrayBE
  data[32..63] = tx.S.toByteArrayBE

  if tx.txType != TxLegacy:
    data[64] = tx.V.byte
  elif tx.V >= EIP155_CHAIN_ID_OFFSET:
    data[64] = byte(1 - (tx.V and 1))
  elif tx.V == 27 or tx.V == 28:
    data[64] = byte(tx.V - 27)
  else:
    return err((errSigPrefixError,"")) # legacy error

  ok(data)

proc encodePreSealed(header: BlockHeader): seq[byte] =
  ## Cut sigature off `extraData` header field.
  if header.extraData.len < EXTRA_SEAL:
    return rlp.encode(header)

  var rlpHeader = header
  rlpHeader.extraData.setLen(header.extraData.len - EXTRA_SEAL)
  rlp.encode(rlpHeader)

proc hashPreSealed(header: BlockHeader): Hash256 =
  ## Returns the hash of a block prior to it being sealed.
  keccakHash header.encodePreSealed


proc recoverImpl(rawSig: openArray[byte]; msg: Hash256): EcAddrResult =
  if rawSig.len < EXTRA_SEAL:
    return err((errMissingSignature,""))

  let sig = Signature.fromRaw(
    rawSig.toOpenArray(rawSig.len - EXTRA_SEAL, rawSig.high))
  if sig.isErr:
    return err((errSkSigResult,$sig.error))

  # Recover the public key from signature and seal hash
  let pubKey = recover(sig.value, SkMessage(msg.data))
  if pubKey.isErr:
    return err((errSkPubKeyResult,$pubKey.error))

  # Convert public key to address.
  ok(pubKey.value.toCanonicalAddress)

# ------------------------------------------------------------------------------
# Public function: straight ecRecover versions
# ------------------------------------------------------------------------------

proc ecRecover*(header: BlockHeader): EcAddrResult =
  header.extraData.recoverImpl(header.hashPreSealed)

proc ecRecover*(tx: var Transaction): EcAddrResult =
  let txSig = tx.vrsSerialised
  if txSig.isErr:
    return err(txSig.error)
  try:
    result = txSig.value.recoverImpl(tx.txHashNoSignature)
  except ValueError as ex:
    return err((errTxEncError, ex.msg))

proc ecRecover*(tx: Transaction): EcAddrResult =
  var ty = tx
  ty.ecRecover

# ------------------------------------------------------------------------------
# Public constructor for caching ecRecover version
# ------------------------------------------------------------------------------

proc init*(er: var EcRecover; cacheSize = INMEMORY_SIGNATURES; initSize = 10) =
  ## Inialise recover cache
  er.size = cacheSize.uint
  er.q.init(initSize)

proc init*(T: type EcRecover;
           cacheSize = INMEMORY_SIGNATURES; initSize = 10): T =
  ## Inialise recover cache
  result.init(cacheSize, initSize)

# ------------------------------------------------------------------------------
# Public functions: miscellaneous
# ------------------------------------------------------------------------------

proc len*(er: var EcRecover): int =
  ## Returns the current number of entries in the LRU cache.
  er.q.len

# ------------------------------------------------------------------------------
# Public functions: caching ecRecover version
# ------------------------------------------------------------------------------

proc ecRecover*(er: var EcRecover; header: var BlockHeader): EcAddrResult =
  info "ecRecover", er=er, header=header

  let key = header.blockHash.data
  block:
    let rc = er.q.lruFetch(key)
    if rc.isOk:
      return ok(rc.value)
  block:
    let rc = header.extraData.recoverImpl(header.hashPreSealed)
    if rc.isOk:
      return ok(er.q.lruAppend(key, rc.value, er.size.int))
    err(rc.error)

proc ecRecover*(er: var EcRecover; header: BlockHeader): EcAddrResult =
  var hdr = header
  er.ecRecover(hdr)

proc ecRecover*(er: var EcRecover; hash: Hash256): EcAddrResult =
  let rc = er.q.lruFetch(hash.data)
  if rc.isOk:
    return ok(rc.value)
  err((errItemNotFound,""))

# ------------------------------------------------------------------------------
# Public RLP mixin functions for caching version
# ------------------------------------------------------------------------------

proc append*(rw: var RlpWriter; data: EcRecover)
    {.raises: [KeyError].} =
  ## Generic support for `rlp.encode()`
  rw.append((data.size,data.q))

proc read*(rlp: var Rlp; Q: type EcRecover): Q
    {.raises: [KeyError].} =
  ## Generic support for `rlp.decode()` for loading the cache from a
  ## serialised data stream.
  (result.size, result.q) = rlp.read((type result.size, type result.q))

# ------------------------------------------------------------------------------
# Debugging
# ------------------------------------------------------------------------------

iterator keyItemPairs*(er: var EcRecover): (EcKey,EthAddress) =
  var rc = er.q.first
  while rc.isOk:
    yield (rc.value.key, rc.value.data)
    rc = er.q.next(rc.value.key)

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
